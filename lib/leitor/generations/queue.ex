defmodule Leitor.Generations.Queue do
  @moduledoc "Supervised dispatch of bounded, uncharged queued requests. Running provider work is never retried automatically."
  use GenServer

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    if Keyword.fetch!(options, :enabled) do
      send(self(), :dispatch)
      {:ok, nil}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:dispatch, state) do
    # Development recompilation may purge domain modules temporarily. Never
    # dispatch while Phoenix's code reloader owns that transition.
    Phoenix.CodeReloader.sync()
    Leitor.Generations.dispatch_queued()
    Process.send_after(self(), :dispatch, 2000)
    {:noreply, state}
  end

  def handle_info({:generation_changed, _id}, state), do: {:noreply, state}
  def handle_info({:page_generation_stage, _id, _stage}, state), do: {:noreply, state}
  def handle_info({:page_generation_delta, _id, _delta}, state), do: {:noreply, state}
  def handle_info({:generation_cancel, _id}, state), do: {:noreply, state}
end
