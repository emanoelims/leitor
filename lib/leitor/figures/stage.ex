defmodule Leitor.Figures.Stage do
  @moduledoc "A physical processing station in a flow figure. Duration is simulated seconds per item, not a claim about real-world measurements."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :label, :string
    field :kind, :string
    field :seconds, :float
  end

  @typedoc "A validated station with an application-owned mechanical assembly."
  @type t :: %__MODULE__{}

  @doc "Casts a bounded station; external code and unknown mechanisms cannot become geometry."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:label, :kind, :seconds])
    |> validate_required([:label, :kind, :seconds])
    |> validate_length(:label, max: 40)
    |> validate_inclusion(:kind, ~w(press scanner wheel))
    |> validate_number(:seconds, greater_than_or_equal_to: 0.8, less_than_or_equal_to: 8)
  end
end
