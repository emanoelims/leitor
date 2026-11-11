defmodule Leitor.Library.Book do
  @moduledoc "An owned book imported from an EPUB, whose chapters are `Leitor.Library.Text` rows ordered by position."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "books" do
    field :title, :string
    field :author, :string
    field :language, :string
    field :identifier, :string
    field :toc, :map, default: %{"entries" => []}
    field :user_id, :binary_id
    field :last_text_id, :binary_id
    field :cover_asset_id, :binary_id
    field :chapter_count, :integer, virtual: true
    field :first_text_id, :binary_id, virtual: true

    timestamps(type: :utc_datetime)
  end

  @typedoc "The persisted record or a record awaiting insertion."
  @type t() :: %__MODULE__{}

  @doc false
  @spec changeset(t(), map(), Leitor.Accounts.Scope.t()) :: Ecto.Changeset.t(t())
  def changeset(book, attrs, user_scope) do
    book
    |> cast(attrs, [:title, :author, :language, :identifier, :toc])
    |> validate_required([:title, :toc])
    |> validate_length(:title, max: 180)
    |> validate_length(:author, max: 180)
    |> validate_length(:language, max: 35)
    |> validate_length(:identifier, max: 255)
    |> put_change(:user_id, user_scope.user.id)
  end
end
