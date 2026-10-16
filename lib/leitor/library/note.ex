defmodule Leitor.Library.Note do
  @moduledoc "A personal note or tutor answer anchored to a sentence in an owned reading."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "reading_notes" do
    field :sentence_index, :integer
    field :quote, :string
    field :body, :string
    field :kind, :string, default: "personal"
    field :question, :string
    field :references, {:array, :integer}, default: []
    belongs_to :text, Leitor.Library.Text
    timestamps(type: :utc_datetime)
  end

  @typedoc "A persisted margin note or an unsaved note awaiting validation."
  @type t() :: %__MODULE__{}

  @doc "Validates note content; the context assigns the parent reading and source quote."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:sentence_index, :body, :kind, :question, :references])
    |> validate_required([:sentence_index, :quote, :body, :kind])
    |> validate_number(:sentence_index, greater_than_or_equal_to: 0)
    |> validate_length(:body, max: 4000)
    |> validate_length(:question, max: 500)
    |> validate_length(:references, max: 40)
    |> validate_inclusion(:kind, ["personal", "tutor"])
    |> foreign_key_constraint(:text_id)
  end
end
