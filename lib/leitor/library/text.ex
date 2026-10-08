defmodule Leitor.Library.Text do
  @moduledoc "Owned text data with validated attributes and UUID v7 identities."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "texts" do
    field :title, :string
    field :body, :string
    field :position, :integer, default: 0
    field :source, :string
    field :analysis, :map, default: %{}
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @typedoc "The persisted record or a record awaiting insertion."
  @type t() :: %__MODULE__{}

  @doc false
  @spec changeset(t(), map(), Leitor.Accounts.Scope.t()) :: Ecto.Changeset.t(t())
  def changeset(text, attrs, user_scope) do
    text
    |> cast(attrs, [:title, :body, :position, :source, :analysis])
    |> validate_required([:title, :body, :position, :source, :analysis])
    |> validate_length(:title, max: 180)
    |> validate_length(:body, max: 300_000)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> put_change(:user_id, user_scope.user.id)
  end
end
