defmodule Leitor.Figures do
  @moduledoc "Versioned figure references and declarative blueprints. Program generation uses an isolated author and reviewed private artifacts; legacy geometry remains data-only."
  alias Leitor.Figures.Flow
  alias Leitor.Figures.Program
  alias Leitor.Figures.Scene

  @engines %{{"anatomy-flow", 1} => Flow, {"anatomy-scene", 1} => Scene, {"anatomy-program", 1} => Program}
  @max_bytes 96_000

  @doc "Decodes a bounded blueprint using only a registered engine and version. Unknown engines never dispatch arbitrary modules."
  @spec decode(term()) :: {:ok, map()} | {:error, :invalid_figure}
  def decode(source) when is_binary(source) and byte_size(source) <= @max_bytes do
    with {:ok, %{"engine" => engine, "version" => version} = attrs} <- Jason.decode(source),
         {:ok, module} <- Map.fetch(@engines, {engine, version}),
         {:ok, figure} <- module.new(attrs) do
      {:ok, Ecto.embedded_dump(figure, :json)}
    else
      _ -> {:error, :invalid_figure}
    end
  end

  def decode(_), do: {:error, :invalid_figure}

  @doc "Produces selectable explanatory Markdown with one validated blueprint. Provider and validation failures do not publish partial figures."
  @spec generate(module(), String.t(), String.t(), Leitor.Language.text_delta_handler(), keyword()) ::
          Leitor.Language.result()
  def generate(adapter, model, prompt, on_delta, options) do
    {scope, options} = Keyword.pop(options, :figure_scope)

    cond do
      scope && Application.get_env(:leitor, :figure_runner, [])[:enabled] ->
        Leitor.Figures.Agent.generate(adapter, model, prompt, scope, on_delta, options)

      Keyword.get(options, :figure_edit, false) ->
        {:error, :runner_unavailable}

      true ->
        generate_scene(
          adapter,
          model,
          prompt,
          on_delta,
          Keyword.drop(options, [:figure_progress, :figure_checkpoint, :figure_revision, :figure_edit])
        )
    end
  end

  defp generate_scene(adapter, model, prompt, on_delta, options) do
    schema = %{
      type: "object",
      additionalProperties: false,
      required: ~w(before figure after),
      properties: %{
        before: %{type: "string", description: "Nonempty explanatory Markdown, up to 3500 characters."},
        figure: Scene.schema(),
        after: %{type: "string", description: "Nonempty experiment instructions, up to 3500 characters."}
      }
    }

    instruction =
      Scene.instruction() <>
        " Write a short explanation before the figure and a useful experiment after it, as Markdown prose without a top-level title. " <>
        "The experiment must name a real control and what change the reader should observe. User request and language: " <>
        prompt

    bounded_options = Keyword.update(options, :max_tokens, 6000, &min(&1, 16_000))

    case adapter.generate(model, instruction, schema, bounded_options) do
      {:ok, %{"before" => before, "figure" => attrs, "after" => after_text}}
      when is_binary(before) and is_map(attrs) and is_binary(after_text) ->
        encode_result(before, attrs, after_text, on_delta)

      {:error, _} = error ->
        error

      _ ->
        {:error, :invalid_response}
    end
  end

  defp encode_result(before, attrs, after_text, on_delta) do
    with %{"engine" => "anatomy-scene", "version" => 1} <- attrs,
         true <-
           String.trim(before) != "" and String.trim(after_text) != "" and byte_size(before) <= 14_000 and
             byte_size(after_text) <= 14_000 and String.length(before) <= 3500 and String.length(after_text) <= 3500,
         {:ok, figure} <- attrs |> Jason.encode!() |> decode() do
      source = Jason.encode!(figure)
      markdown = before <> "\n\n```leitor-figure\n" <> source <> "\n```\n\n" <> after_text

      if String.length(markdown) <= 48_000 and Leitor.Illustration.valid_visual_markdown?(markdown) do
        on_delta.(markdown)
        {:ok, %{"markdown" => markdown}}
      else
        {:error, :invalid_response}
      end
    else
      _ -> {:error, :invalid_response}
    end
  end
end
