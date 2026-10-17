defmodule Leitor.Figures.Part do
  @moduledoc "A freely positioned solid in an authored Anatomy scene. Repetition expands fasteners and ribs; motion stays declarative and bounded."
  use Ecto.Schema

  import Ecto.Changeset

  @fields ~w(name kind position axis size tone repeat spacing radial explode spin profile)a
  @primary_key false
  embedded_schema do
    field :name, :string
    field :kind, :string
    field :position, {:array, :float}
    field :axis, {:array, :float}
    field :size, {:array, :float}
    field :tone, :string
    field :repeat, :integer
    field :spacing, {:array, :float}
    field :radial, :float
    field :explode, {:array, :float}
    field :spin, :float
    field :profile, {:array, {:array, :float}}, default: []
  end

  @typedoc "A validated solid recipe in world coordinates."
  @type t :: %__MODULE__{}

  @doc "Validates primitive geometry and frame directions before the browser constructs paths."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(part, attrs) do
    part
    |> cast(attrs, @fields)
    |> validate_required([:name, :kind, :position, :axis, :size, :tone, :repeat, :spacing, :radial, :explode, :spin])
    |> validate_length(:name, max: 80)
    |> validate_inclusion(:kind, ~w(box cylinder ring sphere gear lathe))
    |> validate_inclusion(:tone, ~w(hi mid lo faint accent))
    |> validate_number(:repeat, greater_than_or_equal_to: 1, less_than_or_equal_to: 24)
    |> validate_number(:radial, greater_than_or_equal_to: 0, less_than_or_equal_to: 200)
    |> validate_number(:spin, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> vector(:position, -400, 400)
    |> vector(:axis, -1, 1)
    |> vector(:size, 0.1, 400)
    |> vector(:spacing, -100, 100)
    |> vector(:explode, -150, 150)
    |> validate_direction()
    |> validate_profile()
    |> validate_ring()
  end

  defp vector(changeset, field, min, max) do
    changeset
    |> validate_length(field, is: 3)
    |> validate_change(field, fn ^field, values ->
      if Enum.all?(values, &(&1 >= min and &1 <= max)), do: [], else: [{field, "has out-of-bounds coordinates"}]
    end)
  end

  defp validate_direction(changeset) do
    case get_field(changeset, :axis) do
      [x, y, z] when x * x + y * y + z * z > 0.01 -> changeset
      _ -> add_error(changeset, :axis, "must have a nonzero direction")
    end
  end

  defp validate_profile(changeset) do
    profile = get_field(changeset, :profile) || []

    if length(profile) <= 12 and Enum.all?(profile, &valid_knot?/1) and
         usable_profile?(get_field(changeset, :kind), profile),
       do: changeset,
       else: add_error(changeset, :profile, "must be a bounded ordered lathe profile")
  end

  defp valid_knot?([along, radius]) when along >= 0 and along <= 400 and radius >= 0 and radius <= 200, do: true
  defp valid_knot?(_knot), do: false

  defp usable_profile?("lathe", profile), do: length(profile) >= 2 and profile == Enum.sort_by(profile, &hd/1)
  defp usable_profile?(_kind, _profile), do: true

  defp validate_ring(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :size)} do
      {"ring", [outer, _length, inner]} when inner >= outer ->
        add_error(changeset, :size, "requires an opening smaller than its outside radius")

      _ ->
        changeset
    end
  end
end
