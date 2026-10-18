defmodule Leitor.FigureAuthorStub do
  @moduledoc false
  def stream_object(_model, prompt, schema, callback, options) do
    send(self(), {:phase, "model", options[:max_tokens]})
    send(self(), {:plan_schema, schema})

    if String.contains?(prompt, "AUTHORING PHASE 1") do
      plan = Map.drop(Leitor.FigureProgramStub.proposal(), ~w(geometry figure))

      plan =
        if Process.get(:reuse_figure_model),
          do: Map.merge(plan, %{"reuse_model" => true, "model" => "", "experiments" => []}),
          else: plan

      callback.(Jason.encode!(plan))
      report_usage(options, 2000)
      {:ok, plan}
    else
      {:error, :invalid_response}
    end
  end

  def stream(_model, prompt, callback, options) do
    phase = if String.contains?(prompt, "AUTHORING PHASE 2"), do: "geometry", else: "figure"
    send(self(), {:phase, phase, options[:max_tokens]})
    source = Map.fetch!(Leitor.FigureProgramStub.proposal(), phase)
    callback.(source)
    report_usage(options, 1000)

    if Process.get(:fail_phase) == phase,
      do: {:error, :provider_error},
      else: {:ok, %{"markdown" => "```js\n#{source}\n```"}}
  end

  defp report_usage(options, tokens) do
    if Process.get(:report_figure_usage) do
      callback = Keyword.fetch!(options, :usage_callback)
      callback.(%{input_tokens: 200, output_tokens: tokens, reasoning_tokens: 300})
    end
  end
end
