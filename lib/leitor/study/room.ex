defmodule Leitor.Study.Room do
  @moduledoc "A private, invitation-only reading room owned by its host."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "rooms" do
    field :title, :string
    field :body, :string
    field :position, :integer, default: 0
    field :invite_code, :string
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @typedoc "A persisted reading room."
  @type t :: %__MODULE__{}

  @doc false
  @spec changeset(t(), map(), Leitor.Accounts.Scope.t()) :: Ecto.Changeset.t()
  def changeset(room, attrs, user_scope) do
    room
    |> cast(attrs, [:title, :body, :position, :invite_code])
    |> validate_required([:title, :body, :position, :invite_code])
    |> validate_length(:title, max: 180)
    |> validate_length(:body, max: 300_000)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint(:invite_code)
    |> put_change(:user_id, user_scope.user.id)
  end
end
