defmodule Leitor.WritingFormat do
  @moduledoc "The generation catalog. Interactive explanatory figures are available; other creative forms remain visible as planned work. Existing documents continue to render."

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
  def visual?(format), do: format in ~w(visual_explainer scientific_diagram explanatory_illustration)

  @doc "Maximum generated Markdown length; blueprints avoid embedding generated path coordinates."
  @spec character_limit(term()) :: pos_integer()
  def character_limit(format) when format in ~w(visual_explainer scientific_diagram explanatory_illustration), do: 48_000
  def character_limit(_format), do: 12_000

  @doc "Returns available generation formats."
  @spec options() :: [{String.t(), String.t()}]
  def options,
    do: [
      {"Interactive figure", "visual_explainer"},
      {"Scientific diagram", "scientific_diagram"},
      {"Explanatory illustration", "explanatory_illustration"}
    ]

  @doc "Returns planned forms, which must not be submitted to the provider."
  @spec planned() :: [{String.t(), String.t()}]
  def planned, do: @planned

  @doc "Returns guidance only for an available format. Unsupported and planned forms return nil."
  @spec instruction(term()) :: String.t() | nil
  def instruction("visual_explainer"),
    do:
      "Create an original interactive mechanism. Derive connected geometry, joints, contact and constrained motion from a pure model. Include real physical supports, meaningful controls, sampled checks and inspectable contact. State idealizations; do not imply a load-rated engineering simulation."

  def instruction("scientific_diagram"),
    do:
      "Create an original interactive scientific diagram. Choose the correct scientific representation: a precise, beautifully composed 2D diagram is appropriate when it explains the phenomenon better than a machine. Implement equations, units, parameter ranges and explicit simplifying assumptions in a pure model. Use state-derived animated rays, particles or phase geometry, useful controls, clear labels and sampled numerical limiting-case/conservation checks. Never fabricate anatomical facts, measurements or physical accuracy. Do not add gears, supports or mechanical perspective to a nonmechanical subject."

  def instruction("explanatory_illustration"),
    do:
      "Create an original explanatory illustration with a coherent visual story and a refined editorial composition. Use intentional color, purposeful detail, readable labels, visual hierarchy and state-derived animation to explain causal changes. Controls must change the actual depicted process, not just decorative colors or text. Implement a pure process model with meaningful transition checks and a useful inspection or comparison. Two-dimensional cutaways and diagrams are valid; do not turn every topic into a factory or mechanism. Explicitly label conceptual simplifications."

  def instruction(_format), do: nil
end
