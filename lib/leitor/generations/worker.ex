defmodule Leitor.Generations.Worker do
  @moduledoc "Supervised ownership of one paid generation. It never restarts a provider request automatically."
  use GenServer, restart: :temporary

  alias Leitor.AI
  alias Leitor.AI.Client
  alias Leitor.Generations
  alias Leitor.Generations.Request

  @doc false
  @spec start_link(tuple()) :: GenServer.on_start()
  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @impl true
  def init({scope, generation, client, preferences}) do
    Generations.subscribe(scope, generation.id)

    task =
      Task.Supervisor.async_nolink(Leitor.GenerationTasks, fn ->
        options =
          client
          |> Client.options()
          |> Keyword.merge(
            figure_scope: scope,
            figure_revision: generation.revision_id,
            figure_edit: not is_nil(generation.request.base_revision_id),
            figure_progress: fn stage ->
              Generations.progress(scope, generation.id, stage)
              Generations.emit(generation.id, {:page_generation_stage, generation.client_id, stage})
            end,
            figure_checkpoint: &Generations.checkpoint(scope, generation.id, &1)
          )

        Leitor.Language.generate_page_text(
          Request.instruction(generation.request),
          fn delta ->
            Generations.emit(generation.id, {:page_generation_delta, generation.client_id, delta})
          end,
          preferences,
          options
        )
      end)

    timer = Process.send_after(self(), :deadline, client.timeout_ms + 1000)
    {:ok, %{scope: scope, generation: generation, task: task, lease_id: client.lease_id, timer: timer}}
  end

  @impl true
  def handle_info({reference, result}, %{task: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    AI.finish(state.scope, state.lease_id)
    Generations.finish(state.scope, state.generation.id, result)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, reference, :process, _pid, _reason}, %{task: %{ref: reference}} = state) do
    AI.finish(state.scope, state.lease_id)
    Generations.finish(state.scope, state.generation.id, {:error, :provider_error})
    {:stop, :normal, state}
  end

  def handle_info({:generation_cancel, _id}, state), do: {:stop, :normal, state}

  def handle_info(:deadline, state) do
    Generations.finish(state.scope, state.generation.id, {:error, :figure_budget_exceeded})
    {:stop, :normal, state}
  end

  def handle_info({:generation_changed, _id}, state), do: {:noreply, state}
  def handle_info({:page_generation_delta, _id, _delta}, state), do: {:noreply, state}
  def handle_info({:page_generation_stage, _id, _stage}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Process.cancel_timer(state.timer)
    Task.shutdown(state.task, :brutal_kill)
    AI.finish(state.scope, state.lease_id)
  end
end
