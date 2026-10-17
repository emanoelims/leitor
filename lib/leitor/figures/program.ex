defmodule Leitor.Figures.Program do
  @moduledoc "A portable reference to a private, reviewed program artifact. Executable code never resides in Markdown."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :engine, :string
    field :version, :integer
    field :title, :string
    field :caption, :string
    field :artifact_id, Ecto.UUID
  end

  @typedoc "A versioned reference whose ownership is checked when its program is loaded."
  @type t :: %__MODULE__{}

  @doc "Validates a reference without loading or executing the program."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:engine, :version, :title, :caption, :artifact_id])
    |> validate_required([:engine, :version, :title, :caption, :artifact_id])
    |> validate_inclusion(:engine, ["anatomy-program"])
    |> validate_inclusion(:version, [1])
    |> validate_length(:title, max: 100)
    |> validate_length(:caption, max: 600)
    |> apply_action(:validate)
  end
end
