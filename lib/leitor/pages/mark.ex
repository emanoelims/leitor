defmodule Leitor.Pages.Mark do
  @moduledoc "A highlight, personal note, definition, or answer anchored to owned page text."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "page_marks" do
    field :from_offset, :integer
    field :to_offset, :integer
    field :block_index, :integer
    field :quote, :string
    field :kind, :string
    field :color, :string, default: "yellow"
    field :body, :string, default: ""
    field :meaning, :string, default: ""
    field :category, :string, default: "word"
    field :question, :string
    embeds_many :replies, Leitor.Pages.Reply, on_replace: :delete
    belongs_to :text, Leitor.Library.Text
    timestamps(type: :utc_datetime)
  end

  @typedoc "A saved page annotation."
  @type t() :: %__MODULE__{}

  @doc "Validates annotation content; ownership and anchors are assigned by the context."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(mark, attrs) do
    mark
    |> cast(attrs, [:kind, :color, :body, :meaning, :category, :question], empty_values: [])
    |> validate_required([:quote, :kind, :color, :category])
    |> validate_inclusion(:kind, ~w(highlight note definition answer))
    |> validate_inclusion(:color, ~w(yellow green blue rose))
    |> validate_inclusion(:category, ~w(word noun verb aux adj adv pron prep det conj proper expression))
    |> validate_length(:body, max: 4000)
    |> validate_length(:meaning, max: 2000)
    |> validate_length(:question, max: 500)
    |> require_body()
    |> foreign_key_constraint(:text_id)
  end

  defp require_body(changeset) do
    if get_field(changeset, :kind) != "highlight" and String.trim(get_field(changeset, :body) || "") == "",
      do: add_error(changeset, :body, "can't be blank"),
      else: changeset
  end
end
