defmodule Leitor.Learning.Entry do
  @moduledoc "Owned entry data with validated attributes and UUID v7 identities."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "entries" do
    field :term, :string
    field :meaning, :string
    field :category, :string
    field :context, :string
    field :status, :string
    field :interval, :integer
    field :due_at, :utc_datetime
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @typedoc "The persisted record or a record awaiting insertion."
  @type t() :: %__MODULE__{}

  @doc false
  @spec changeset(t(), map(), Leitor.Accounts.Scope.t()) :: Ecto.Changeset.t(t())
  def changeset(entry, attrs, user_scope) do
    entry
    |> cast(attrs, [:term, :meaning, :category, :context, :status, :interval, :due_at])
    |> validate_required([:term, :meaning, :category, :context, :status, :interval, :due_at])
    |> validate_length(:term, max: 200)
    |> validate_length(:meaning, max: 2000)
    |> validate_number(:interval, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :term])
    |> put_change(:user_id, user_scope.user.id)
  end
end
