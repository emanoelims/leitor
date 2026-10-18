defmodule Leitor.AI do
  @moduledoc "Scoped AI credentials, shared spending limits, and expiring execution authorizations. All product AI requests reserve credits before contacting a provider."
  import Ecto.Query

  alias Ecto.Changeset
  alias Leitor.Accounts
  alias Leitor.Accounts.Scope
  alias Leitor.AI.Bucket
  alias Leitor.AI.Client
  alias Leitor.AI.Credential
  alias Leitor.AI.Policy
  alias Leitor.AI.Reservation
  alias Leitor.AI.Usage
  alias Leitor.AI.Vault
  alias Leitor.Repo

  require Logger

  @typedoc "Supported credit-charged product operations."
  @type operation :: :read | :write | :illustration
  @typedoc "Recoverable authorization failures that never contain provider secrets."
  @type error :: :quota_exceeded | :busy | :credential_unavailable
  @typedoc "Provider metadata safe to return to the caller; keys and ciphertext are never included."
  @type credential_info :: %{id: Ecto.UUID.t(), provider: String.t(), hint: String.t()}
  @typedoc "Current UTC-day account credit counters and server-configured ceilings."
  @type usage :: %{
          used: non_neg_integer(),
          limit: pos_integer(),
          personal_used: non_neg_integer(),
          personal_limit: pos_integer()
        }
  @shared_model "anthropic:claude-haiku-5-5"

  @doc "Returns the only model allowed on the application-owned text credential."
  @spec shared_model() :: String.t()
  def shared_model, do: @shared_model

  @doc "Reads validated server-side limits; invalid operator configuration fails closed."
  @spec policy() :: Policy.t()
  def policy do
    {:ok, policy} = Policy.new(Application.get_env(:leitor, :ai_limits, %{}))
    policy
  end

  @doc "Lists only safe credential metadata belonging to the caller. Plaintext and ciphertext are omitted."
  @spec credentials(Scope.t()) :: [credential_info()]
  def credentials(%Scope{user: %{id: id}}) do
    Repo.all(
      from c in Credential,
        where: c.user_id == ^id,
        order_by: c.provider,
        select: %{id: c.id, provider: c.provider, hint: c.hint}
    )
  end

  @doc "Creates or replaces an account provider key after validation and authenticated encryption. The returned value contains no secret."
  @spec put_credential(Scope.t(), Credential.attrs()) :: {:ok, credential_info()} | {:error, Changeset.t(Credential.t())}
  def put_credential(%Scope{user: %{id: id}}, attrs) do
    with {:ok, credential} <- validate_credential(id, attrs) do
      encrypted = Vault.encrypt(credential.api_key, id, credential.provider)
      hint = String.slice(credential.api_key, -4, 4)
      changeset = Changeset.change(credential, encrypted_key: encrypted, hint: hint)

      case Repo.insert(changeset,
             on_conflict: {:replace, [:encrypted_key, :hint, :updated_at]},
             conflict_target: [:user_id, :provider],
             returning: true
           ) do
        {:ok, stored} -> {:ok, %{id: stored.id, provider: stored.provider, hint: stored.hint}}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc "Removes only the caller's provider key. Unknown or foreign identifiers raise Ecto.NoResultsError."
  @spec delete_credential(Scope.t(), Ecto.UUID.t()) :: {:ok, Credential.t()} | {:error, Changeset.t()}
  def delete_credential(%Scope{user: %{id: user_id}}, id) do
    Credential |> Repo.get_by!(id: id, user_id: user_id) |> Repo.delete()
  end

  @doc "Returns the caller's daily shared and personal credit counts. The UTC date defines the daily period."
  @spec usage(Scope.t()) :: usage()
  def usage(%Scope{user: %{id: id}}) do
    policy = policy()
    bucket = Repo.get(Bucket, user_bucket(id))

    %{
      used: if(bucket, do: bucket.used, else: 0),
      limit: policy.daily_limit,
      personal_used: if(bucket, do: bucket.personal_used, else: 0),
      personal_limit: policy.personal_daily_limit
    }
  end

  @doc "Reserves credits and concurrency atomically. Shared requests always use Haiku; a personal Anthropic key unlocks the account's selected Claude model. Failed and canceled attempts are charged, and crashed leases expire after their bounded provider and planning timeouts."
  @spec prepare(Scope.t(), operation()) :: {:ok, Client.t()} | {:error, error()}
  def prepare(%Scope{user: %{id: user_id}} = scope, operation) when operation in [:read, :write, :illustration] do
    preferences = Accounts.get_preferences(scope)
    credential = Repo.get_by(Credential, user_id: user_id, provider: "anthropic")

    with {:ok, key} <- credential_key(credential) do
      mode = if credential, do: "personal", else: "shared"
      model = if mode == "shared", do: shared_model(), else: personal_model(operation, preferences)

      {:ok, client} =
        Client.new(%{
          lease_id: Ecto.UUID.generate(),
          model: model,
          mode: mode,
          api_key: key,
          max_tokens: token_budget(operation, mode),
          timeout_ms: if(operation == :illustration and mode == "personal", do: 1_200_000, else: 90_000)
        })

      reserve(user_id, operation, client)
    end
  end

  defp reserve(user_id, operation, client) do
    now = DateTime.utc_now(:second)
    credits = Map.fetch!(%{read: 1, write: 2, illustration: 4}, operation)
    limits = policy()

    Repo.transact(fn ->
      # A stable lock also serializes reservations across the UTC date boundary.
      lock_bucket("capacity")
      global = lock_bucket("global:#{DateTime.to_date(now)}")
      account = lock_bucket("user:#{user_id}:#{DateTime.to_date(now)}")

      with :ok <- check_allowance(client.mode, account, global, credits, limits),
           :ok <- check_capacity(user_id, account, now, limits) do
        charge(account, global, credits, client.mode, now)

        Repo.insert!(%Reservation{
          id: client.lease_id,
          user_id: user_id,
          operation: Atom.to_string(operation),
          mode: client.mode,
          model: client.model,
          outcome: "running",
          credits: credits,
          expires_at:
            DateTime.shift(now,
              second:
                div(client.timeout_ms, 1000) +
                  if(operation == :illustration and client.mode == "personal", do: 120, else: 30)
            )
        })

        {:ok, client}
      end
    end)
  end

  defp check_allowance("shared", account, global, credits, limits) do
    if account.used + credits > limits.daily_limit or global.used + credits > limits.global_daily_limit,
      do: {:error, :quota_exceeded},
      else: :ok
  end

  defp check_allowance("personal", account, _global, credits, limits) do
    if account.personal_used + credits > limits.personal_daily_limit, do: {:error, :quota_exceeded}, else: :ok
  end

  @doc "Reports whether a global lease slot is available. Reservation remains atomic; this scheduling hint never authorizes provider use."
  @spec capacity_available?() :: boolean()
  def capacity_available? do
    now = DateTime.utc_now()

    Repo.aggregate(from(r in Reservation, where: is_nil(r.finished_at) and r.expires_at > ^now), :count) <
      policy().global_concurrent
  end

  defp check_capacity(user_id, account, now, limits) do
    active = from r in Reservation, where: is_nil(r.finished_at) and r.expires_at > ^now

    cooldown? =
      not is_nil(account.last_started_at) and DateTime.diff(now, account.last_started_at) < limits.cooldown_seconds

    if cooldown? or Repo.aggregate(active, :count) >= limits.global_concurrent or
         Repo.aggregate(from(r in active, where: r.user_id == ^user_id), :count) >= limits.max_concurrent,
       do: {:error, :busy},
       else: :ok
  end

  defp charge(account, global, credits, mode, now) do
    field = if mode == "shared", do: :used, else: :personal_used
    Repo.update_all(from(b in Bucket, where: b.key == ^account.key), inc: [{field, credits}], set: [last_started_at: now])
    if mode == "shared", do: Repo.update_all(from(b in Bucket, where: b.key == ^global.key), inc: [used: credits])
  end

  @doc "Releases the caller's concurrency lease idempotently. Credits are never refunded."
  @spec finish(Scope.t(), Ecto.UUID.t() | nil) :: :ok
  @spec finish(Scope.t(), Ecto.UUID.t() | nil, :completed | :failed | :cancelled | :expired) :: :ok
  def finish(scope, id, outcome \\ :completed)
  def finish(_scope, nil, _outcome), do: :ok

  def finish(%Scope{user: %{id: user_id}}, id, outcome) when outcome in [:completed, :failed, :cancelled, :expired] do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {_count, changed} =
      Repo.update_all(
        from(r in Reservation,
          where: r.id == ^id and r.user_id == ^user_id and is_nil(r.finished_at),
          select: map(r, [:operation, :mode, :model, :inserted_at])
        ),
        set: [finished_at: now, outcome: Atom.to_string(outcome)]
      )

    Enum.each(changed, fn attempt ->
      duration = max(0, DateTime.diff(now, attempt.inserted_at, :millisecond))
      metadata = Map.put(Map.take(attempt, [:operation, :mode, :model]), :outcome, outcome)
      :telemetry.execute([:leitor, :ai, :attempt, :stop], %{duration_ms: duration, count: 1}, metadata)

      Logger.info(
        "ai_attempt_finished operation=#{attempt.operation} mode=#{attempt.mode} outcome=#{outcome} duration_ms=#{duration}"
      )
    end)

    :ok
  end

  @doc "Returns request-local options with a scoped measurement callback. Neither keys nor provider content are stored in usage records."
  @spec execution_options(Scope.t(), Client.t()) :: keyword()
  def execution_options(scope, client) do
    Keyword.put(Client.options(client), :usage_callback, &record_usage(scope, client.lease_id, &1))
  end

  @doc "Adds one actual provider response to its owned reservation atomically. Missing/invalid usage increments an unmeasured counter instead of inventing free requests."
  @spec record_usage(Scope.t(), Ecto.UUID.t(), map()) :: :ok
  def record_usage(%Scope{user: %{id: user_id}}, id, attrs) do
    reservation = Repo.get_by!(Reservation, id: id, user_id: user_id)

    increments =
      case Usage.new(attrs) do
        {:ok, usage} ->
          cost = Usage.estimate(usage, reservation.model)

          [
            input_tokens: usage.input_tokens,
            output_tokens: usage.output_tokens,
            cache_read_tokens: usage.cache_read_tokens,
            cache_write_tokens: usage.cache_write_tokens,
            estimated_cost_micros: cost || 0,
            measured_calls: if(cost, do: 1, else: 0),
            unmeasured_calls: if(cost, do: 0, else: 1)
          ]

        {:error, _changeset} ->
          [unmeasured_calls: 1]
      end

    Repo.update_all(from(r in Reservation, where: r.id == ^id and r.user_id == ^user_id), [inc: increments], log: false)
    :ok
  end

  @doc "Lists the caller's twenty most recent measurements without prompts, provider errors, credentials or generated code. Expired unfinished leases are labeled expired."
  @spec recent_attempts(Scope.t()) :: [map()]
  def recent_attempts(%Scope{user: %{id: user_id}}) do
    now = DateTime.utc_now()

    from(r in Reservation,
      where: r.user_id == ^user_id,
      order_by: [desc: r.inserted_at, desc: r.id],
      limit: 20,
      select:
        map(r, [
          :id,
          :operation,
          :mode,
          :credits,
          :model,
          :outcome,
          :input_tokens,
          :output_tokens,
          :cache_read_tokens,
          :cache_write_tokens,
          :estimated_cost_micros,
          :measured_calls,
          :unmeasured_calls,
          :inserted_at,
          :finished_at,
          :expires_at
        ])
    )
    |> Repo.all()
    |> Enum.map(fn attempt ->
      outcome =
        if is_nil(attempt.finished_at) and DateTime.compare(attempt.expires_at, now) != :gt,
          do: "expired",
          else: attempt.outcome

      Map.put(attempt, :outcome, outcome)
    end)
  end

  @doc "Summarizes the caller's current UTC-day measurements and active leases. Costs are estimates; missing calls remain visible. No other account's activity is exposed."
  @spec activity(Scope.t()) :: map()
  def activity(%Scope{user: %{id: user_id}}) do
    now = DateTime.utc_now()
    start = DateTime.new!(Date.utc_today(), ~T[00:00:00])

    Repo.one(
      from r in Reservation,
        where: r.user_id == ^user_id and r.inserted_at >= ^start,
        select: %{
          attempts: count(r.id),
          input_tokens: fragment("coalesce(sum(?), 0)::bigint", r.input_tokens),
          output_tokens: fragment("coalesce(sum(?), 0)::bigint", r.output_tokens),
          cost: fragment("coalesce(sum(?), 0)::bigint", r.estimated_cost_micros),
          measured_calls: fragment("coalesce(sum(?), 0)::bigint", r.measured_calls),
          unmeasured_calls: fragment("coalesce(sum(?), 0)::bigint", r.unmeasured_calls),
          incomplete_attempts:
            filter(count(r.id), r.measured_calls == 0 or is_nil(r.outcome) or r.outcome != "completed"),
          active: filter(count(r.id), is_nil(r.finished_at) and r.expires_at > ^now)
        }
    )
  end

  defp validate_credential(id, attrs),
    do: %Credential{user_id: id} |> Credential.changeset(attrs) |> Changeset.apply_action(:insert)

  defp credential_key(nil), do: {:ok, nil}

  defp credential_key(credential) do
    case Vault.decrypt(credential.encrypted_key, credential.user_id, credential.provider) do
      {:ok, key} -> {:ok, key}
      {:error, :invalid_credential} -> {:error, :credential_unavailable}
    end
  end

  defp lock_bucket(key) do
    Repo.insert!(%Bucket{key: key}, on_conflict: :nothing)
    Repo.one!(from b in Bucket, where: b.key == ^key, lock: "FOR UPDATE")
  end

  defp token_budget(:read, _mode), do: 2500
  defp token_budget(:illustration, "personal"), do: 65_536
  defp token_budget(_, _), do: 6000

  defp personal_model(operation, preferences) do
    model = if operation == :read, do: preferences.reading_model, else: preferences.writing_model
    if model == "default", do: shared_model(), else: model
  end

  defp user_bucket(id), do: "user:#{id}:#{Date.utc_today()}"
end
