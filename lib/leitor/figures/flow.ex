defmodule Leitor.Figures.Flow do
  @moduledoc "Version one of the Anatomy-backed flow workbench. A portable blueprint preserves the explanation and simulation; geometry is reconstructed by the bundled drawing kit."
  @behaviour Leitor.Figures.Engine

  use Ecto.Schema

  import Ecto.Changeset

  alias Leitor.Figures.Stage

  @primary_key false
  embedded_schema do
    field :engine, :string
    field :version, :integer
    field :title, :string
    field :caption, :string
    field :accent, :string
    field :queue_limit, :integer
    field :arrival_seconds, :float
    embeds_many :stages, Stage
  end

  @typedoc "A validated, bounded workbench blueprint with two to four processing stations."
  @type t :: %__MODULE__{}

  @doc "Constructs a versioned flow blueprint. Invalid geometry recipes, text or simulation limits return a changeset."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  @impl true
  def new(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:engine, :version, :title, :caption, :accent, :queue_limit, :arrival_seconds])
    |> validate_required([:engine, :version, :title, :caption, :accent, :queue_limit, :arrival_seconds])
    |> validate_inclusion(:engine, ["anatomy-flow"])
    |> validate_inclusion(:version, [1])
    |> validate_inclusion(:accent, ~w(amber blue mint rose))
    |> validate_length(:title, max: 100)
    |> validate_length(:caption, max: 600)
    |> validate_number(:queue_limit, greater_than_or_equal_to: 1, less_than_or_equal_to: 8)
    |> validate_number(:arrival_seconds, greater_than_or_equal_to: 0.5, less_than_or_equal_to: 8)
    |> cast_embed(:stages, required: true)
    |> validate_length(:stages, min: 2, max: 4)
    |> apply_action(:validate)
  end

  @doc "Returns an Anthropic-compatible structural schema. Bounds are described here and enforced by new/1, rather than unsupported JSON Schema constraint keywords."
  @spec schema() :: map()
  @impl true
  def schema do
    %{
      type: "object",
      additionalProperties: false,
      required: ~w(engine version title caption accent queue_limit arrival_seconds stages),
      properties: %{
        engine: %{type: "string", enum: ["anatomy-flow"]},
        version: %{type: "integer", enum: [1]},
        title: %{type: "string", description: "Nonempty title, at most 100 characters."},
        caption: %{type: "string", description: "Nonempty caption, at most 600 characters."},
        accent: %{type: "string", enum: ~w(amber blue mint rose)},
        queue_limit: %{type: "integer", description: "Integer between 1 and 8 inclusive."},
        arrival_seconds: %{type: "number", description: "Between 0.5 and 8 simulated seconds inclusive."},
        stages: %{
          type: "array",
          description: "Between two and four sequential stations.",
          items: %{
            type: "object",
            additionalProperties: false,
            required: ~w(label kind seconds),
            properties: %{
              label: %{type: "string", description: "Nonempty label, at most 40 characters."},
              kind: %{type: "string", enum: ~w(press scanner wheel)},
              seconds: %{
                type: "number",
                description: "Processing duration between 0.8 and 8 simulated seconds inclusive."
              }
            }
          }
        }
      }
    }
  end

  @doc "Describes the physical vocabulary and truthful explanatory limits of the first engine."
  @spec instruction() :: String.t()
  @impl true
  def instruction do
    "Design a crafted physical workbench explaining the user's topic as a flow of discrete items through 2–4 sequential stations. " <>
      "The app builds precise isometric solid geometry with Anatomy: feet, bevelled base, rails, conveyor rollers, bolts, guides, processing mechanisms, control dials, pressure gauge and independent moving items. " <>
      "You design the causal model, station sequence and pacing, not SVG coordinates. Choose kind press for transformation, scanner for inspection, wheel for circulation. " <>
      "Each station holds one item; completed work waits if the next station is occupied. The first buffer holds queue_limit items; new arrivals are rejected when it is full. " <>
      "An item advances only after seconds of processing at each station. Choose different times to make the bottleneck observable. arrival_seconds sets the automatic input interval. " <>
      "Users can add one item, send a burst, pause individual stations, change speed, pause the whole machine, and reset. The readout reports actual queue, completion and rejection counts. " <>
      "Make the metaphor specific, coherent and instructive. Use the user's explicitly requested language for EVERY visible field: title, caption, station labels and explanatory prose. Caption must explain the mapping and state that timing is illustrative. " <>
      "Do not invent measured scientific values. Do not claim arbitrary machines, fluids, character art or physical laws are simulated. Explain the boundary of the analogy if the topic does not naturally form a workflow. " <>
      "Use a restrained accent and concise station labels. Output data only: no HTML, CSS, SVG, code, links, or instructions for the runtime."
  end
end
