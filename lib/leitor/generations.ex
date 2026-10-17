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

  @doc "Validates and reserves one figure attempt, resuming only an unchanged owned request. The worker survives its editor."
  @spec start(Scope.t(), Ecto.UUID.t() | nil, map()) :: {:ok, Generation.t()} | {:error, start_error()}
  def start(%Scope{user: %{id: user_id}} = scope, page_id, attrs) do
    if page_id, do: Leitor.Pages.get_page!(scope, page_id)
    changeset = Generation.changeset(%Generation{user_id: user_id, text_id: page_id}, attrs)

    with {:ok, validated} <- Ecto.Changeset.apply_action(changeset, :insert),
         :ok <- authorize_revision(scope, validated.request),
         {:ok, client} <- AI.prepare(scope, :illustration) do
      create_attempt(scope, validated, page_id, client)
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
        AI.finish(scope, client.lease_id)
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

      {:error, _reason} ->
        finish(scope, generation.id, {:error, :provider_error})
        AI.finish(scope, client.lease_id)
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
  @spec await(Scope.t(), Ecto.UUID.t()) :: Leitor.Language.result()
  def await(scope, id) do
    subscribe(scope, id)
    wait(scope, id)
  end

  defp wait(scope, id) do
    generation = scope |> get!(id) |> then(&expire(scope, &1))

    case generation.status do
      "ready" ->
        {:ok, %{"markdown" => generation.markdown}}

      "running" ->
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
    generation = get!(scope, id)
    finish(scope, id, {:error, :cancelled})
    Phoenix.PubSub.broadcast(Leitor.PubSub, topic(id), {:generation_cancel, id})
    AI.finish(scope, generation.lease_id)
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
  @spec finish(Scope.t(), Ecto.UUID.t(), Leitor.Language.result() | {:error, :cancelled}) :: :ok
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

    update_running(scope, id, attrs)
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

  defp expire(scope, %{status: "running"} = generation) do
    if DateTime.after?(generation.expires_at, DateTime.utc_now()) do
      generation
    else
      finish(scope, generation.id, {:error, :figure_budget_exceeded})
      emit(generation.id, {:generation_cancel, generation.id})
      AI.finish(scope, generation.lease_id)
      get!(scope, generation.id)
    end
  end

  defp expire(_scope, generation), do: generation
  defp owned(%Scope{user: %{id: id}}), do: from(g in Generation, where: g.user_id == ^id)
  defp topic(id), do: "page-generation:#{id}"

  defp error_atom(error) do
    errors =
      ~w(unavailable invalid_input invalid_response provider_error runner_unavailable runner_timeout figure_review_failed figure_budget_exceeded)a

    Enum.find(errors, :provider_error, &(Atom.to_string(&1) == error))
  end
end
