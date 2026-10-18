defmodule Leitor.Generations.Worker do
  @moduledoc "Supervised ownership of one paid generation. It never restarts a provider request automatically."
  use GenServer, restart: :temporary

  alias Leitor.AI
  alias Leitor.Generations
  alias Leitor.Generations.Request

  @doc false
  @spec start_link(tuple()) :: GenServer.on_start()
  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @impl true
  def init({scope, generation, client, preferences}) do
    Generations.subscribe(scope, generation.id)

    if Generations.get!(scope, generation.id).status == "running" do
      start_work(scope, generation, client, preferences)
    else
      :ignore
    end
  end

  defp start_work(scope, generation, client, preferences) do
    job_id = generation.id
    client_id = generation.client_id
    revision_id = generation.revision_id
    editing = not is_nil(generation.request.base_revision_id)
    request = Request.instruction(generation.request)

    task =
      Task.Supervisor.async_nolink(Leitor.GenerationTasks, fn ->
        options =
          scope
          |> AI.execution_options(client)
          |> Keyword.merge(
            figure_scope: scope,
            figure_revision: revision_id,
            figure_edit: editing,
            figure_progress: fn stage ->
              Generations.progress(scope, job_id, stage)
              Generations.emit(job_id, {:page_generation_stage, client_id, stage})
            end,
            figure_checkpoint: &Generations.checkpoint(scope, job_id, &1)
          )

        Leitor.Language.generate_page_text(
          request,
          fn delta ->
            Generations.emit(job_id, {:page_generation_delta, client_id, delta})
          end,
          preferences,
          options
        )
      end)

    timer = Process.send_after(self(), :deadline, client.timeout_ms + 1000)
    {:ok, %{scope: scope, generation_id: job_id, task: task, lease_id: client.lease_id, timer: timer}}
  end

  @impl true
  def handle_info({reference, result}, %{task: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    AI.finish(state.scope, state.lease_id, if(match?({:ok, _}, result), do: :completed, else: :failed))
    Generations.finish(state.scope, state.generation_id, result)
    {:stop, :normal, %{state | lease_id: nil}}
  end

  def handle_info({:DOWN, reference, :process, _pid, _reason}, %{task: %{ref: reference}} = state) do
    AI.finish(state.scope, state.lease_id, :failed)
    Generations.finish(state.scope, state.generation_id, {:error, :provider_error})
    {:stop, :normal, %{state | lease_id: nil}}
  end

  def handle_info({:generation_cancel, _id}, state) do
    AI.finish(state.scope, state.lease_id, :cancelled)
    {:stop, :normal, %{state | lease_id: nil}}
  end

  def handle_info(:deadline, state) do
    Task.shutdown(state.task, :brutal_kill)
    AI.finish(state.scope, state.lease_id, :expired)
    Generations.finish(state.scope, state.generation_id, {:error, :figure_budget_exceeded})
    {:stop, :normal, %{state | lease_id: nil}}
  end

  def handle_info({:generation_changed, _id}, state), do: {:noreply, state}
  def handle_info({:page_generation_delta, _id, _delta}, state), do: {:noreply, state}
  def handle_info({:page_generation_stage, _id, _stage}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Process.cancel_timer(state.timer)
    Task.shutdown(state.task, :brutal_kill)
    AI.finish(state.scope, state.lease_id, :failed)
  end
end
