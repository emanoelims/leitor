defmodule Leitor.Generations do
  @moduledoc "Durable, account-scoped figure attempts. Browser disconnects do not own or cancel provider work."
  import Ecto.Query

  alias Leitor.Accounts
  alias Leitor.Accounts.Scope
  alias Leitor.AI
  alias Leitor.Figures.Artifacts
  alias Leitor.Generations.Generation
  alias Leitor.Generations.Request
  alias Leitor.Generations.Worker
  alias Leitor.Repo

  @typedoc "Recoverable request, authorization or worker startup errors."
  @type start_error :: AI.error() | Ecto.Changeset.t() | :worker_unavailable | :invalid_input

  @doc "Validates a figure attempt and either reserves execution or saves one uncharged queued request when capacity is busy. Queue admission is capped at fifty globally and one waiting job per account; waiting expires after ten minutes. The worker survives its editor."
  @spec start(Scope.t(), Ecto.UUID.t() | nil, map()) :: {:ok, Generation.t()} | {:error, start_error()}
  def start(%Scope{user: %{id: user_id}} = scope, page_id, attrs) do
    if page_id, do: Leitor.Pages.get_page!(scope, page_id)
    changeset = Generation.changeset(%Generation{user_id: user_id, text_id: page_id}, attrs)

    with {:ok, validated} <- Ecto.Changeset.apply_action(changeset, :insert),
         :ok <- authorize_revision(scope, validated.request) do
      case AI.prepare(scope, :illustration) do
        {:ok, client} -> create_attempt(scope, validated, page_id, client)
        {:error, :busy} -> enqueue(scope, validated)
        {:error, _} = error -> error
      end
    end
  end

  defp enqueue(scope, validated) do
    revision = retry_revision(latest(scope, validated.text_id), validated.request)

    result =
      Repo.transact(fn ->
        # Admission is serialized across nodes; this lock never owns provider work.
        Repo.query!("SELECT pg_advisory_xact_lock(0, $1)", [16_171_001], log: false)
        queued = from g in Generation, where: g.status == "queued"

        if Repo.aggregate(queued, :count) >= 50 or Repo.exists?(from g in queued, where: g.user_id == ^scope.user.id) do
          {:error, :busy}
        else
          validated
          |> Ecto.Changeset.change(
            status: "queued",
            stage: "queued",
            revision_id: revision,
            expires_at: DateTime.shift(DateTime.utc_now(:second), minute: 10)
          )
          |> Repo.insert(log: false)
        end
      end)

    case result do
      {:ok, generation} ->
        subscribe(scope, generation.id)
        {:ok, generation}

      {:error, _} = error ->
        error
    end
  end

  @doc "Counts the caller's waiting, not-yet-charged requests. At most one request per account may wait."
  @spec queued_count(Scope.t()) :: non_neg_integer()
  def queued_count(scope),
    do:
      Repo.aggregate(from(g in owned(scope), where: g.status == "queued" and g.expires_at > ^DateTime.utc_now()), :count)

  @doc false
  @spec dispatch_queued() :: :ok
  def dispatch_queued do
    now = DateTime.utc_now()

    expired =
      Repo.all(
        from(g in Generation,
          where: g.status == "queued" and g.expires_at <= ^now,
          limit: 50,
          select: map(g, [:id, :user_id])
        ),
        log: false
      )

    Enum.each(expired, fn job ->
      scope = job.user_id |> Accounts.get_user!() |> Scope.for_user()
      finish(scope, job.id, {:error, :figure_budget_exceeded})
    end)

    if AI.capacity_available?() do
      jobs =
        Repo.all(
          from(g in Generation, where: g.status == "queued", order_by: g.id, limit: 50, select: map(g, [:id, :user_id])),
          log: false
        )

      dispatch_available(jobs)
    else
      :ok
    end
  end

  defp dispatch_available(jobs) do
    Enum.reduce_while(jobs, :ok, fn job, :ok ->
      scope = job.user_id |> Accounts.get_user!() |> Scope.for_user()
      dispatch(scope, job)
      if AI.capacity_available?(), do: {:cont, :ok}, else: {:halt, :ok}
    end)
  end

  defp dispatch(scope, job) do
    result =
      Repo.transact(fn ->
        current =
          Repo.one(
            from(g in owned(scope), where: g.id == ^job.id and g.status == "queued", lock: "FOR UPDATE SKIP LOCKED"),
            log: false
          )

        cond do
          is_nil(current) ->
            {:ok, :skip}

          DateTime.compare(current.expires_at, DateTime.utc_now()) != :gt ->
            {:error, :figure_budget_exceeded}

          true ->
            reserve_queued(scope, current)
        end
      end)

    case result do
      {:ok, {generation, client}} ->
        launch(scope, generation, client)
        unsubscribe(generation.id)
        emit(generation.id, {:generation_changed, generation.id})
        emit(generation.id, {:page_generation_stage, generation.client_id, "building"})

      {:ok, :skip} ->
        :ok

      {:error, :busy} ->
        :ok

      {:error, reason} ->
        finish(scope, job.id, {:error, reason})
    end
  end

  defp reserve_queued(scope, current) do
    with {:ok, client} <- AI.prepare(scope, :illustration) do
      generation =
        current
        |> Ecto.Changeset.change(
          status: "running",
          stage: "building",
          lease_id: client.lease_id,
          expires_at: DateTime.shift(DateTime.utc_now(:second), second: div(client.timeout_ms, 1000) + 120)
        )
        |> Repo.update!(log: false)

      {:ok, {generation, client}}
    end
  end

  defp create_attempt(scope, validated, page_id, client) do
    previous = latest(scope, page_id)
    revision = retry_revision(previous, validated.request)

    changeset =
      Ecto.Changeset.change(validated,
        revision_id: revision,
        lease_id: client.lease_id,
        expires_at:
          DateTime.utc_now() |> DateTime.shift(second: div(client.timeout_ms, 1000) + 120) |> DateTime.truncate(:second)
      )

    case Repo.insert(changeset, log: false) do
      {:ok, generation} ->
        launch(scope, generation, client)

      {:error, changeset} ->
        AI.finish(scope, client.lease_id, :failed)
        {:error, changeset}
    end
  end

  defp retry_revision(nil, request), do: request.base_revision_id

  defp retry_revision(previous, request) do
    if Request.instruction(previous.request) == Request.instruction(request) &&
         previous.request.base_revision_id == request.base_revision_id,
       do: previous.revision_id || request.base_revision_id,
       else: request.base_revision_id
  end

  defp launch(scope, generation, client) do
    subscribe(scope, generation.id)
    preferences = Accounts.get_preferences(scope)

    child = {Worker, {scope, generation, client, preferences}}

    case DynamicSupervisor.start_child(Leitor.GenerationSupervisor, child) do
      {:ok, _pid} ->
        {:ok, generation}

      :ignore ->
        AI.finish(scope, client.lease_id, :cancelled)
        {:ok, get!(scope, generation.id)}

      {:error, _reason} ->
        finish(scope, generation.id, {:error, :provider_error})
        AI.finish(scope, client.lease_id, :failed)
        {:error, :worker_unavailable}
    end
  end

  defp authorize_revision(_scope, %{base_revision_id: nil}), do: :ok

  defp authorize_revision(scope, %{base_revision_id: id}) do
    if Artifacts.get_ready(scope, id), do: :ok, else: {:error, :invalid_input}
  end

  @doc "Reads the latest undismissed attempt for this editor, without exposing another account's work."
  @spec latest(Scope.t(), Ecto.UUID.t() | nil) :: Generation.t() | nil
  def latest(scope, page_id) do
    query = from g in owned(scope), where: g.dismissed == false, order_by: [desc: g.id], limit: 1

    query =
      if page_id, do: from(g in query, where: g.text_id == ^page_id), else: from(g in query, where: is_nil(g.text_id))

    case Repo.one(query) do
      nil -> nil
      generation -> expire(scope, generation)
    end
  end

  @doc "Fetches a caller-owned attempt; inaccessible identifiers raise Ecto.NoResultsError."
  @spec get!(Scope.t(), Ecto.UUID.t()) :: Generation.t()
  def get!(scope, id), do: Repo.one!(from g in owned(scope), where: g.id == ^id)

  @doc "Subscribes this process to an owned attempt's progress."
  @spec subscribe(Scope.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe(scope, id) do
    get!(scope, id)
    Phoenix.PubSub.subscribe(Leitor.PubSub, topic(id))
  end

  @doc false
  @spec unsubscribe(Ecto.UUID.t()) :: :ok
  def unsubscribe(id), do: Phoenix.PubSub.unsubscribe(Leitor.PubSub, topic(id))

  @doc false
  @spec emit(Ecto.UUID.t(), term()) :: :ok | {:error, term()}
  def emit(id, event), do: Phoenix.PubSub.broadcast(Leitor.PubSub, topic(id), event)

  @doc "Waits for a durable result without owning the worker. Terminating the waiter never cancels generation."
  @spec await(Scope.t(), Ecto.UUID.t()) :: Leitor.Language.result() | {:error, AI.error()}
  def await(scope, id) do
    subscribe(scope, id)
    wait(scope, id)
  end

  defp wait(scope, id) do
    generation = scope |> get!(id) |> then(&expire(scope, &1))

    case generation.status do
      "ready" ->
        {:ok, %{"markdown" => generation.markdown}}

      status when status in ["running", "queued"] ->
        receive do
          {:generation_changed, ^id} -> wait(scope, id)
          _event -> wait(scope, id)
        after
          30_000 -> wait(scope, id)
        end

      _ ->
        {:error, error_atom(generation.error)}
    end
  end

  @doc "Requests cancellation of an owned active attempt; private checkpoints remain recoverable."
  @spec cancel(Scope.t(), Ecto.UUID.t()) :: :ok
  def cancel(scope, id) do
    {:ok, _} =
      Repo.transact(fn ->
        generation = Repo.one!(from g in owned(scope), where: g.id == ^id, lock: "FOR UPDATE")

        if generation.status in ["running", "queued"] do
          finish(scope, id, {:error, :cancelled})
          AI.finish(scope, generation.lease_id, :cancelled)
          emit(id, {:generation_cancel, id})
        end

        {:ok, :cancelled}
      end)

    :ok
  end

  @doc "Dismisses an owned recovery notice after the user saves or explicitly discards it."
  @spec dismiss(Scope.t(), Ecto.UUID.t()) :: :ok
  def dismiss(scope, id) do
    scope |> get!(id) |> Ecto.Changeset.change(dismissed: true) |> Repo.update!(log: false)
    :ok
  end

  @doc false
  @spec progress(Scope.t(), Ecto.UUID.t(), String.t()) :: :ok
  def progress(scope, id, stage) do
    update_running(scope, id, stage: stage)
    :ok
  end

  @doc false
  @spec checkpoint(Scope.t(), Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def checkpoint(scope, id, revision) do
    if Artifacts.get_revision(scope, revision), do: update_running(scope, id, revision_id: revision)
    :ok
  end

  @doc false
  @spec finish(Scope.t(), Ecto.UUID.t(), Leitor.Language.result() | {:error, :cancelled | AI.error()}) :: :ok
  def finish(scope, id, result) do
    attrs =
      case result do
        {:ok, %{"markdown" => markdown}} when is_binary(markdown) and byte_size(markdown) <= 1_200_000 ->
          [status: "ready", stage: "ready", markdown: markdown, error: nil]

        {:error, reason} when is_atom(reason) ->
          [status: "failed", error: Atom.to_string(reason)]

        _ ->
          [status: "failed", error: "provider_error"]
      end

    update_active(scope, id, attrs)
    :ok
  end

  defp update_running(scope, id, attrs) do
    Repo.update_all(
      from(g in owned(scope), where: g.id == ^id and g.status == "running"),
      [set: Keyword.put(attrs, :updated_at, DateTime.truncate(DateTime.utc_now(), :second))],
      log: false
    )

    Phoenix.PubSub.broadcast(Leitor.PubSub, topic(id), {:generation_changed, id})
  end

  defp update_active(scope, id, attrs) do
    Repo.update_all(
      from(g in owned(scope), where: g.id == ^id and g.status in ["running", "queued"]),
      [set: Keyword.put(attrs, :updated_at, DateTime.utc_now(:second))],
      log: false
    )

    emit(id, {:generation_changed, id})
  end

  defp expire(scope, %{status: status} = generation) when status in ["running", "queued"] do
    if DateTime.after?(generation.expires_at, DateTime.utc_now()) do
      generation
    else
      finish(scope, generation.id, {:error, :figure_budget_exceeded})
      emit(generation.id, {:generation_cancel, generation.id})
      AI.finish(scope, generation.lease_id, :expired)
      get!(scope, generation.id)
    end
  end

  defp expire(_scope, generation), do: generation
  defp owned(%Scope{user: %{id: id}}), do: from(g in Generation, where: g.user_id == ^id)
  defp topic(id), do: "page-generation:#{id}"

  defp error_atom(error) do
    errors =
      ~w(unavailable invalid_input invalid_response provider_error runner_unavailable runner_timeout figure_review_failed figure_budget_exceeded quota_exceeded busy credential_unavailable)a

    Enum.find(errors, :provider_error, &(Atom.to_string(&1) == error))
  end
end
