defmodule Leitor.FigureContinuationGate do
  @moduledoc false

  def generate(_model, prompt, _schema, _options) do
    event = if String.contains?(prompt, "Repair your previous program"), do: :figure_repaired, else: :figure_authored
    send(Application.fetch_env!(:leitor, :language_test_owner), {event, self()})
    {:ok, Leitor.FigureProgramStub.proposal()}
  end

  def review(_model, _prompt, _images, _schema, _options) do
    send(Application.fetch_env!(:leitor, :language_test_owner), {:figure_review, self()})

    receive do
      {:complete, accept} -> {:ok, %{"accept" => accept, "critique" => "The joint must remain attached."}}
    end
  end
end
