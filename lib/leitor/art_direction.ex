defmodule Leitor.ArtDirection do
  @moduledoc "A bounded art-direction pass for personal-key illustrated generation. Composition, continuity and meaningful layer motion are planned before the final page is drawn."
  require Logger

  @doc "Adds a concise visual plan using the caller's model and request-local credential. Shared requests use the supplied direction without an additional provider call."
  @spec prepare(module(), String.t(), String.t(), String.t(), keyword()) :: {:ok, String.t()} | Leitor.Language.result()
  def prepare(adapter, model, prompt, direction, options) do
    if Keyword.get(options, :api_key) do
      plan(adapter, model, prompt, direction, options)
    else
      {:ok, direction}
    end
  end

  defp plan(adapter, model, prompt, direction, options) do
    schema = %{
      type: "object",
      properties: %{direction: %{type: "string", maxLength: 4000}},
      required: ["direction"],
      additionalProperties: false
    }

    format_brief = direction |> String.split("Create editorial-quality", parts: 2) |> hd() |> String.slice(0, 800)

    instruction =
      "Act as a senior illustrator and motion designer. Plan an exceptional original reading illustration, not a placeholder or icon. Specify a cohesive visual language, a restrained palette, concrete silhouettes/anatomy or precisely projected isometric geometry, foreground/midground/background, focal contrast, negative space, and deliberate line weights. For a comic, specify consistent character traits and distinct cinematic shots. For animated diagrams, specify which semantic layers move, why, timing, and which remain still. Favor a few carefully constructed, detailed elements over a large number of generic circles. Describe specific drawable geometry and purposeful motion; do not claim to have seen a render. Keep the direction concise, under 2500 characters. User brief: #{inspect(prompt)}. Selected form: #{inspect(format_brief)}. Do not draw the artwork or write the page now. Return only a concise verbal art-direction plan in the direction field: no SVG, code, markup or scene JSON."

    options =
      options
      |> Keyword.drop([:total_timeout, :stream_idle_timeout, :reasoning_effort])
      |> Keyword.put(:max_tokens, 4096)
      |> Keyword.put(:receive_timeout, 90_000)

    case adapter.generate(model, instruction, schema, options) do
      {:ok, %{"direction" => plan}} when is_binary(plan) and byte_size(plan) <= 6000 ->
        {:ok, direction <> "\nArt direction to implement: " <> plan}

      {:error, _} = error ->
        error

      {:ok, %{"direction" => plan}} when is_binary(plan) ->
        Logger.warning("Art direction exceeded its size limit: #{byte_size(plan)} bytes")
        {:error, :invalid_response}

      _ ->
        Logger.warning("Art direction returned an invalid object")
        {:error, :invalid_response}
    end
  end
end
