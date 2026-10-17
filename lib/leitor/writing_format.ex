defmodule Leitor.WritingFormat do
  @moduledoc "The generation catalog. Interactive explanatory figures are available; other creative forms remain visible as planned work. Existing documents continue to render."
  alias Leitor.Figures.Scene

  @planned [
    {"Illustrated story", "illustrated_story"},
    {"Illustrated poem", "illustrated_poem"},
    {"Manga", "manga"},
    {"Animated scene", "animated_scene"},
    {"Free text", "free"},
    {"Poem", "poem"},
    {"Short story", "story"},
    {"Dialogue", "dialogue"},
    {"Article", "article"}
  ]

  @doc "Whether a format requires the illustration authorization and budget."
  @spec visual?(term()) :: boolean()
  def visual?(format), do: format == "visual_explainer"

  @doc "Maximum generated Markdown length; blueprints avoid embedding generated path coordinates."
  @spec character_limit(term()) :: pos_integer()
  def character_limit("visual_explainer"), do: 48_000
  def character_limit(_format), do: 12_000

  @doc "Returns available generation formats."
  @spec options() :: [{String.t(), String.t()}]
  def options, do: [{"Interactive figure", "visual_explainer"}]

  @doc "Returns planned forms, which must not be submitted to the provider."
  @spec planned() :: [{String.t(), String.t()}]
  def planned, do: @planned

  @doc "Returns guidance only for an available format. Unsupported and planned forms return nil."
  @spec instruction(term()) :: String.t() | nil
  def instruction("visual_explainer"), do: Scene.instruction()
  def instruction(_format), do: nil
end
