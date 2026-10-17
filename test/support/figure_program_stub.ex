defmodule Leitor.FigureProgramStub do
  @moduledoc false
  def proposal do
    experiment = %{
      "name" => "A real action",
      "steps" => [%{"action" => "click", "selector" => "#turn", "value" => ""}],
      "selector" => "#status",
      "contains" => "Blocked"
    }

    %{
      "title" => "A lock",
      "caption" => "An idealized lock",
      "before" => "Read the mechanism.",
      "after" => "Try the wrong key.",
      "figure" => "export function mount(root){root.textContent='lock'}",
      "geometry" => "export const shape=1",
      "model" => "export const state=1",
      "css" => "svg{width:100%}",
      "checks" => "export function verify(){return [1,2,3].map(n=>({name:String(n),passed:true}))}",
      "experiments" => [experiment, experiment, experiment]
    }
  end

  def generate(_model, _prompt, _schema, options) do
    send(self(), {:allocation, Keyword.fetch!(options, :max_tokens)})

    case Process.get(:figure_proposal, proposal()) do
      [first | rest] ->
        Process.put(:figure_proposal, rest)
        {:ok, first}

      source ->
        {:ok, source}
    end
  end

  def review(_model, _prompt, _images, _schema, options) do
    send(self(), {:allocation, Keyword.fetch!(options, :max_tokens)})

    accept =
      case Process.get(:accept_figure, true) do
        [first | rest] ->
          Process.put(:accept_figure, rest)
          first

        value ->
          value
      end

    {:ok,
     %{
       "accept" => accept,
       "critique" => "Check construction and motion.",
       "explanation_consistent" => Process.get(:consistent_explanation, true),
       "explanation_evidence" => "The stated limit agrees with the sampled model."
     }}
  end

  def check(_files) do
    send(self(), :isolated_figure_checked)

    {:ok,
     %{
       report: %{"ok" => true, "images" => ["light.png"], "checks" => [%{"passed" => true}]},
       images: [<<137, 80, 78, 71>>],
       bundle: "(()=>{})();",
       style: "svg{width:100%}"
     }}
  end
end
