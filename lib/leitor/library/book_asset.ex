defmodule Leitor.Library.BookAsset do
  @moduledoc """
  An image imported with a book, served only to the book's readers.

  The bytes are either in `data` or, when object storage is configured, in the object named by `storage_key`.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "book_assets" do
    field :book_id, :binary_id
    field :content_type, :string
    field :byte_size, :integer
    field :digest, :binary
    field :data, :binary
    field :storage_key, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @typedoc "The persisted record or a record awaiting insertion."
  @type t() :: %__MODULE__{}
end
