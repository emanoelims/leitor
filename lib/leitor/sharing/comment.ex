defmodule Leitor.Sharing.Comment do
  @moduledoc "A shared, attributed comment or reply with a server-validated source quotation."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type :binary_id
  schema "page_comments" do
    field :visitor_id, Ecto.UUID
    field :author_name, :string
    field :body, :string
    field :quote, :string
    field :from_offset, :integer
    field :to_offset, :integer
    field :block_index, :integer
    field :deleted_at, :utc_datetime
    belongs_to :share, Leitor.Sharing.Share
    belongs_to :user, Leitor.Accounts.User
    belongs_to :parent, __MODULE__
    timestamps(type: :utc_datetime)
  end

  @typedoc "A comment; account IDs and guest identity are never supplied through the form changeset."
  @type t :: %__MODULE__{}
  @doc "Validates bounded plain-text content and a display name. Source and author identities are set separately."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:author_name, :body])
    |> update_change(:author_name, &String.trim/1)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:author_name, :body])
    |> validate_length(:author_name, max: 60)
    |> validate_length(:body, max: 4000)
  end
end
