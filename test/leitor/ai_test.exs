defmodule Leitor.AITest do
  use Leitor.DataCase

  import Leitor.AccountsFixtures

  alias Leitor.Accounts
  alias Leitor.AI
  alias Leitor.AI.Bucket
  alias Leitor.AI.Client
  alias Leitor.AI.Credential
  alias Leitor.AI.Policy
  alias Leitor.AI.Reservation
  alias Leitor.AI.Vault

  setup do
    old = Application.get_env(:leitor, :ai_limits)
    Application.put_env(:leitor, :ai_limits, %{cooldown_seconds: 0})
    on_exit(fn -> Application.put_env(:leitor, :ai_limits, old) end)
    %{scope: user_scope_fixture()}
  end

  test "keys are encrypted, redacted, upserted and scoped", %{scope: scope} do
    other = user_scope_fixture()
    key = "test-private-provider-1234"
    assert {:ok, metadata} = AI.put_credential(scope, %{provider: "anthropic", api_key: key, user_id: other.user.id})
    assert metadata.hint == "1234"
    stored = Repo.get!(Credential, metadata.id)
    assert stored.user_id == scope.user.id
    assert stored.api_key == nil
    refute stored.encrypted_key =~ key
    refute inspect(%{stored | api_key: key}) =~ key
    assert {:ok, ^key} = Vault.decrypt(stored.encrypted_key, scope.user.id, "anthropic")
    assert {:error, :invalid_credential} = Vault.decrypt(stored.encrypted_key, other.user.id, "anthropic")
    assert {:error, :invalid_credential} = Vault.decrypt(stored.encrypted_key, scope.user.id, "openai")
    assert {:error, :invalid_credential} = Vault.decrypt(<<0>> <> stored.encrypted_key, scope.user.id, "anthropic")
    assert Vault.encrypt(key, scope.user.id, "anthropic") != stored.encrypted_key
    assert AI.credentials(other) == []
    assert AI.credentials(scope) == [metadata]
    assert_raise Ecto.NoResultsError, fn -> AI.delete_credential(other, metadata.id) end
    assert {:ok, replaced} = AI.put_credential(scope, %{provider: "anthropic", api_key: "replacement-account-key-5678"})
    assert replaced.id == metadata.id
    assert replaced.hint == "5678"
    assert {:ok, _} = AI.delete_credential(scope, metadata.id)
    assert AI.credentials(scope) == []

    for attrs <- [
          %{},
          %{provider: "unsupported", api_key: key},
          %{provider: "openai", api_key: "short"},
          %{provider: "openai", api_key: "key with spaces invalid"}
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = AI.put_credential(scope, attrs)
    end
  end

  # ReqLLM derives thinking options from LLMDB; an uncatalogued model receives
  # budgeted thinking, which Claude 5.5 models reject with HTTP 400.
  test "offered Claude models are catalogued with adaptive thinking" do
    for model <- [AI.shared_model(), "anthropic:claude-sonnet-5-5", "anthropic:claude-opus-5-5"] do
      assert {:ok, metadata} = ReqLLM.model(model)
      assert ReqLLM.ModelHelpers.adaptive_thinking_required?(metadata), model
    end
  end

  test "shared key is always Haiku despite saved premium choices", %{scope: scope} do
    {:ok, _} =
      Accounts.update_preferences(scope, %{
        reading_model: "anthropic:claude-opus-5-5",
        writing_model: "anthropic:claude-sonnet-5-5"
      })

    for operation <- [:read, :write, :illustration] do
      assert {:ok, client} = AI.prepare(scope, operation)
      assert client.mode == "shared"
      assert client.model == AI.shared_model()
      assert Keyword.get(Client.options(client), :api_key) == nil
      assert client.max_tokens <= 6000
      assert :ok = AI.finish(scope, client.lease_id)
      assert :ok = AI.finish(scope, client.lease_id)
    end

    assert AI.usage(scope).used == 7
  end

  test "own Anthropic credential unlocks models without using shared credits and never leaks across accounts", %{
    scope: scope
  } do
    key = "own-anthropic-account-key"
    {:ok, _} = AI.put_credential(scope, %{provider: "anthropic", api_key: key})
    {:ok, _} = Accounts.update_preferences(scope, %{reading_model: "anthropic:claude-opus-5-5"})
    assert {:ok, personal} = AI.prepare(scope, :read)
    assert personal.model == "anthropic:claude-opus-5-5"
    assert personal.mode == "personal"
    assert Client.options(personal)[:api_key] == key
    assert {:ok, %{token: ^key, kind: :api_key}} = ReqLLM.Auth.resolve(:anthropic, Client.options(personal))
    refute inspect(personal) =~ key
    assert AI.usage(scope) == %{used: 0, limit: 20, personal_used: 1, personal_limit: 200}
    other = user_scope_fixture()
    assert {:ok, shared} = AI.prepare(other, :read)
    refute Client.options(shared)[:api_key]
    assert :ok = AI.finish(other, personal.lease_id)
    assert {:error, :busy} = AI.prepare(scope, :read)
    AI.finish(scope, personal.lease_id)
    AI.finish(other, shared.lease_id)
    assert {:ok, default} = AI.prepare(scope, :write)
    assert default.model == AI.shared_model()
  end

  test "personal artwork has a bounded drawing budget without raising shared limits", %{scope: scope} do
    assert {:ok, shared} = AI.prepare(scope, :illustration)
    assert shared.max_tokens == 6000
    assert shared.timeout_ms == 90_000
    refute Client.options(shared)[:reasoning_effort]
    AI.finish(scope, shared.lease_id)
    {:ok, _} = AI.put_credential(scope, %{provider: "anthropic", api_key: "personal-artwork-provider-key"})
    {:ok, _} = Accounts.update_preferences(scope, %{writing_model: "anthropic:claude-opus-5-5"})
    assert {:ok, personal} = AI.prepare(scope, :illustration)
    assert personal.model == "anthropic:claude-opus-5-5"
    assert personal.max_tokens == 65_536
    assert Client.options(personal)[:reasoning_effort] == :low
    assert Client.options(personal)[:total_timeout] == 1_200_000
    lease = Repo.get!(Reservation, personal.lease_id)
    assert DateTime.diff(lease.expires_at, lease.inserted_at) == 1320
    AI.finish(scope, personal.lease_id)
    assert {:ok, writing} = AI.prepare(scope, :write)
    assert writing.max_tokens == 6000
    refute Client.options(writing)[:reasoning_effort]
    attrs = %{lease_id: Ecto.UUID.generate(), mode: "shared", model: AI.shared_model(), max_tokens: 6000}
    assert {:error, _} = Client.new(Map.put(attrs, :timeout_ms, nil))
    assert {:error, _} = Client.new(Map.put(attrs, :timeout_ms, 480_001))
  end

  test "daily account and global limits count canceled attempts and cannot overdraw", %{scope: scope} do
    Application.put_env(:leitor, :ai_limits, %{daily_limit: 4, global_daily_limit: 5, cooldown_seconds: 0})
    assert {:ok, client} = AI.prepare(scope, :illustration)
    assert {:error, :quota_exceeded} = AI.prepare(scope, :read)
    AI.finish(scope, client.lease_id)
    assert {:error, :quota_exceeded} = AI.prepare(scope, :write)
    other = user_scope_fixture()
    assert {:ok, final} = AI.prepare(other, :read)
    AI.finish(other, final.lease_id)
    assert {:error, :quota_exceeded} = AI.prepare(other, :read)
    assert AI.usage(scope).used == 4
    assert AI.usage(other).used == 1
    assert Repo.aggregate(Reservation, :count) == 2
  end

  test "account and global concurrency, cooldown and stale leases are enforced", %{scope: scope} do
    assert {:ok, first} = AI.prepare(scope, :read)
    assert {:error, :busy} = AI.prepare(scope, :write)
    other = user_scope_fixture()
    assert {:ok, second} = AI.prepare(other, :read)
    third = user_scope_fixture()
    assert {:error, :busy} = AI.prepare(third, :read)
    AI.finish(scope, first.lease_id)
    Application.put_env(:leitor, :ai_limits, %{cooldown_seconds: 60})
    assert {:error, :busy} = AI.prepare(scope, :read)
    Application.put_env(:leitor, :ai_limits, %{cooldown_seconds: 0})
    Repo.update_all(Reservation, set: [expires_at: DateTime.shift(DateTime.utc_now(:second), minute: -1)])
    assert {:ok, _} = AI.prepare(other, :read)
    assert Repo.get!(Reservation, second.lease_id).finished_at == nil
  end

  test "corrupted own keys fail closed, other provider keys never unlock Claude, and personal usage is capped", %{
    scope: scope
  } do
    {:ok, _} = AI.put_credential(scope, %{provider: "openai", api_key: "future-image-provider-key"})
    assert {:ok, shared} = AI.prepare(scope, :read)
    assert shared.mode == "shared"
    AI.finish(scope, shared.lease_id)
    {:ok, credential} = AI.put_credential(scope, %{provider: "anthropic", api_key: "own-provider-account-key"})
    Application.put_env(:leitor, :ai_limits, %{personal_daily_limit: 2, cooldown_seconds: 0})
    assert {:ok, personal} = AI.prepare(scope, :write)
    AI.finish(scope, personal.lease_id)
    assert {:error, :quota_exceeded} = AI.prepare(scope, :read)
    Repo.update_all(from(c in Credential, where: c.id == ^credential.id), set: [encrypted_key: <<1, 2, 3>>])
    assert {:error, :credential_unavailable} = AI.prepare(scope, :read)
    assert AI.usage(scope).personal_used == 2
    assert AI.usage(scope).used == 1
  end

  test "simultaneous account requests reserve a single lease without double spending", %{scope: scope} do
    parent = self()

    workers =
      for n <- 1..6 do
        task =
          start_supervised!(
            {Task,
             fn ->
               receive do
                 :reserve -> send(parent, {:reservation_result, AI.prepare(scope, :read)})
               end
             end},
            id: {:reservation_test, n}
          )

        send(task, :reserve)
        task
      end

    results =
      for _ <- workers do
        assert_receive {:reservation_result, result}, 2000
        result
      end

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :busy})) == 5
    assert AI.usage(scope).used == 1
    assert Repo.aggregate(Reservation, :count) == 1
  end

  test "server policy and execution constructors validate bounds" do
    assert {:ok, %Policy{daily_limit: 20}} = Policy.new(%{})

    for attrs <- [
          %{daily_limit: 0},
          %{global_concurrent: -1},
          %{cooldown_seconds: 3601},
          %{daily_limit: "unlimited"},
          %{daily_limit: nil}
        ] do
      assert {:error, _} = Policy.new(attrs)
    end

    assert {:error, _} = Client.new(%{mode: "root", max_tokens: 100_000})
    assert Repo.aggregate(Bucket, :count) == 0
  end
end
