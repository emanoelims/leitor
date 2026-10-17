defmodule Leitor.Illustration.Motion do
  @moduledoc "Validated, declarative motion for a named vector layer. The browser implements only these fixed animation primitives."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :target, :string
    field :kind, :string
    field :axis, :string, default: "y"
    field :from, :float, default: 0.0
    field :to, :float, default: 1.0
    field :duration, :integer, default: 3000
    field :delay, :integer, default: 0
    field :direction, :string, default: "alternate"
    field :easing, :string, default: "ease-in-out"
  end

  @typedoc "A bounded animation targeting one local SVG identifier."
  @type t :: %__MODULE__{}
  @doc "Validates motion types, timing and value ranges; arbitrary properties or executable code are unsupported."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(motion, attrs) do
    motion
    |> cast(attrs, [:target, :kind, :axis, :from, :to, :duration, :delay, :direction, :easing])
    |> validate_required([:target, :kind, :axis, :from, :to, :duration, :delay, :direction, :easing])
    |> validate_format(:target, ~r/^[A-Za-z][A-Za-z0-9_-]{0,80}$/)
    |> validate_inclusion(:kind, ~w(translate rotate scale opacity draw))
    |> validate_inclusion(:axis, ~w(x y))
    |> validate_inclusion(:direction, ~w(normal reverse alternate alternate-reverse))
    |> validate_inclusion(:easing, ~w(linear ease-in ease-out ease-in-out))
    |> validate_number(:duration, greater_than_or_equal_to: 600, less_than_or_equal_to: 30_000)
    |> validate_number(:delay, greater_than_or_equal_to: 0, less_than_or_equal_to: 15_000)
    |> validate_values()
  end

  defp validate_values(changeset) do
    {min, max} =
      case get_field(changeset, :kind) do
        kind when kind in ~w(opacity draw) -> {0, 1}
        "scale" -> {0.1, 3}
        "rotate" -> {-360, 360}
        _ -> {-2000, 2000}
      end

    Enum.reduce(
      [:from, :to],
      changeset,
      &validate_number(&2, &1, greater_than_or_equal_to: min, less_than_or_equal_to: max)
    )
  end
end
