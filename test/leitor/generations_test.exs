defmodule Leitor.GenerationsTest do
  use Leitor.DataCase, async: false

  import Leitor.AccountsFixtures
  import Leitor.FigureFixtures

  alias Leitor.Generations
  alias Leitor.Generations.Generation

  setup do
    previous = Application.get_env(:leitor, :language_adapter)
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageGate)
    Application.put_env(:leitor, :language_test_owner, self())

    on_exit(fn ->
      Application.put_env(:leitor, :language_adapter, previous)
      Application.delete_env(:leitor, :language_test_owner)
    end)

    %{scope: user_scope_fixture()}
  end

  defp attrs do
    %{
      client_id: "durable",
      request: %{prompt: "A connected mechanism", title: "Mechanism", context: "", draft_body: "Keep my text."}
    }
  end

  test "a completed attempt is recoverable without another reservation or provider call", %{scope: scope} do
    assert {:ok, job} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, task}
    usage = Leitor.AI.usage(scope)
    send(task, {:complete, {:ok, figure_response("Done.")}})
    assert {:ok, %{"markdown" => markdown}} = Generations.await(scope, job.id)
    assert markdown =~ "Done."
    assert Generations.latest(scope, nil).id == job.id
    assert Generations.latest(scope, nil).request.draft_body == "Keep my text."
    assert Leitor.AI.usage(scope) == usage
    refute_receive {:language_started, _}
  end

  test "only the owning account can fetch, stop or dismiss a generation", %{scope: scope} do
    {:ok, job} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, task}
    monitor = Process.monitor(task)
    other = user_scope_fixture()
    assert Generations.latest(other, nil) == nil
    assert_raise Ecto.NoResultsError, fn -> Generations.get!(other, job.id) end
    assert_raise Ecto.NoResultsError, fn -> Generations.cancel(other, job.id) end
    assert_raise Ecto.NoResultsError, fn -> Generations.dismiss(other, job.id) end
    assert :ok = Generations.cancel(scope, job.id)
    assert_receive {:DOWN, ^monitor, :process, ^task, _}
    assert Generations.get!(scope, job.id).status == "failed"
    assert :ok = Generations.dismiss(scope, job.id)
    assert Generations.latest(scope, nil) == nil
  end

  test "expired attempts release capacity and stop their provider process", %{scope: scope} do
    {:ok, job} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, task}
    monitor = Process.monitor(task)

    job
    |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.shift(second: -1) |> DateTime.truncate(:second))
    |> Repo.update!()

    assert Generations.latest(scope, nil).error == "figure_budget_exceeded"
    assert_receive {:DOWN, ^monitor, :process, ^task, _}
  end

  test "malformed snapshots and foreign figure revisions never reserve AI credits", %{scope: scope} do
    assert {:error, %Ecto.Changeset{}} = Generations.start(scope, nil, put_in(attrs(), [:request, :prompt], " "))

    revision_request =
      update_in(
        attrs(),
        [:request],
        &Map.merge(&1, %{base_revision_id: Ecto.UUID.generate(), replace_from: 0, replace_to: 1})
      )

    assert {:error, :invalid_input} = Generations.start(scope, nil, revision_request)

    assert Leitor.AI.usage(scope).used == 0
    assert Repo.all(Generation) == []
    refute_receive {:language_started, _}
  end
end
