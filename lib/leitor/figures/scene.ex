defmodule Leitor.Figures.Scene do
  @moduledoc "An authored composition of independent solids, with no imposed apparatus or station layout. The model specifies geometry; Anatomy projects, shades and frames it."
  @behaviour Leitor.Figures.Engine

  use Ecto.Schema

  import Ecto.Changeset

  alias Leitor.Figures.Part

  @primary_key false
  embedded_schema do
    field :engine, :string
    field :version, :integer
    field :title, :string
    field :caption, :string
    field :accent, :string
    field :azimuth, :float
    field :elevation, :float
    embeds_many :parts, Part
  end

  @typedoc "An independently authored composition with bounded geometry and motion."
  @type t :: %__MODULE__{}

  @doc "Validates the scene and its total expanded geometry budget. Existing flow blueprints remain separate."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  @impl true
  def new(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:engine, :version, :title, :caption, :accent, :azimuth, :elevation])
    |> validate_required([:engine, :version, :title, :caption, :accent, :azimuth, :elevation])
    |> validate_inclusion(:engine, ["anatomy-scene"])
    |> validate_inclusion(:version, [1])
    |> validate_length(:title, max: 100)
    |> validate_length(:caption, max: 600)
    |> validate_inclusion(:accent, ~w(amber blue mint rose))
    |> validate_number(:azimuth, greater_than_or_equal_to: 0, less_than_or_equal_to: 360)
    |> validate_number(:elevation, greater_than_or_equal_to: 15, less_than_or_equal_to: 65)
    |> cast_embed(:parts, required: true)
    |> validate_length(:parts, min: 8, max: 100)
    |> validate_budget()
    |> apply_action(:validate)
  end

  defp validate_budget(changeset) do
    parts = get_field(changeset, :parts, [])

    if Enum.sum(Enum.map(parts, &(&1.repeat || 0))) <= 400,
      do: changeset,
      else: add_error(changeset, :parts, "exceed the 400-solid budget")
  end

  @doc "Returns the structural provider schema. Numeric bounds are enforced by changesets."
  @spec schema() :: map()
  @impl true
  def schema do
    vector = %{type: "array", items: %{type: "number"}, description: "Exactly three finite world coordinates."}

    fields = %{
      name: %{type: "string"},
      kind: %{type: "string", enum: ~w(box cylinder ring sphere gear lathe)},
      position: vector,
      axis: vector,
      size: vector,
      spacing: vector,
      explode: vector,
      tone: %{type: "string", enum: ~w(hi mid lo faint accent)},
      repeat: %{type: "integer"},
      radial: %{type: "number"},
      spin: %{type: "number"},
      profile: %{type: "array", items: %{type: "array", items: %{type: "number"}}}
    }

    %{
      type: "object",
      additionalProperties: false,
      required: ~w(engine version title caption accent azimuth elevation parts),
      properties: %{
        engine: %{type: "string", enum: ["anatomy-scene"]},
        version: %{type: "integer", enum: [1]},
        title: %{type: "string"},
        caption: %{type: "string"},
        accent: %{type: "string", enum: ~w(amber blue mint rose)},
        azimuth: %{type: "number"},
        elevation: %{type: "number"},
        parts: %{
          type: "array",
          items: %{
            type: "object",
            additionalProperties: false,
            required: Enum.map(Map.keys(fields), &Atom.to_string/1),
            properties: fields
          }
        }
      }
    }
  end

  @doc "Supplies the construction vocabulary and craft rules for original subject-specific objects."
  @spec instruction() :: String.t()
  @impl true
  def instruction do
    "AUTHOR AN ORIGINAL OBJECT, not a variation of a stock workbench. Invent the actual subject-specific apparatus before choosing parts. " <>
      "There is NO predefined base, conveyor, station, layout, part placement or geometry. You specify all solids freely in world coordinates; Anatomy handles projection, shading and curved surfaces. " <>
      "A telescope should look like a telescope, a lock like a lock, an orrery like an orrery. Do not force everything into a factory metaphor. " <>
      "Build 20–60 part definitions, at least 40 expanded solids with repetition, maximum 100 definitions/400 solids. Each part has a concise meaningful name. " <>
      "Coordinates: x,y on the floor, z up; bounds -400..400. position is the centre of a primitive's starting cross-section. axis is its direction, a nonzero vector with coordinates -1..1; [0,0,1] is vertical, [1,0,0] horizontal. " <>
      "size is always three positive values 0.1..400. box: [width,depth,height], centred across its axis and extending height along axis. cylinder/gear: [radius,length,unused=1]; ring: [outer_radius,length,inner_radius], with inner<outer. sphere: [radius,1,1]. lathe uses profile ordered pairs [axial_distance,radius], up to 12 pairs, distance 0..400 radius 0..200. Other shapes use profile:[]. " <>
      "repeat 1..24, spacing:[dx,dy,dz] advances successive copies; radial>0 places copies around their axis at that radius, radial=0 is linear. Default repeat:1 spacing:[0,0,0] radial:0. " <>
      "Copies retain the SAME axis: never use radial repetition for splayed tripod legs, spokes pointing different ways, or rotated supports. Define those parts individually with their own axes and correct contact endpoints. " <>
      "explode:[dx,dy,dz] is each assembly's offset when the user opens it (each coordinate -150..150); related parts must share offsets and remain recognisable. spin is rotation degrees per second about the part's own axis (-180..180), zero for structural parts. Geared wheels must have meaningful relative rotation and believable shaft contact. " <>
      "tone hi/mid/lo/faint/accent; use one accent sparingly on the explanatory subject. azimuth 0..360 (usually 40–60), elevation 15..65 (usually 28–35). " <>
      "CRAFT: coherent silhouette, real thickness, collars, bevel-like thin caps, feet, fasteners, bearings, retaining rings, contact surfaces and structural supports. Every part rests on or connects to another. No floating decorations or meaningless detail. " <>
      "Do not overlap solid shafts through solid caps; use rings at apertures. Do not bury a subject behind opaque shells: show cutaway segments or an exploded assembly. Use separate pieces for mechanisms so their motion is meaningful. " <>
      "Controls supplied: open the assembly, run/pause its moving parts, change speed, turn the camera, select individual parts to inspect names. Explain exactly what those controls reveal. This is an illustrated mechanism, not a validated scientific physics simulation. " <>
      "Only declared spin and explode movements occur. Do not claim automatic linkages, gear ratios, translations, unlocking conditions or optical simulation that you have not represented. Explain real-world operation separately from what the illustration actually animates. " <>
      "All visible text uses the user's explicitly requested language. title <=100 characters, caption <=600. No SVG paths, code, HTML, styles or network references. Return an original, detailed construction, never a stock apparatus."
  end
end
