defmodule Leitor.Learning.Attempt do
  @moduledoc "Owned attempt data with validated attributes and UUID v7 identities."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "attempts" do
    field :kind, :string
    field :content, :string
    field :result, :map
    field :duration, :integer
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @typedoc "The persisted record or a record awaiting insertion."
  @type t() :: %__MODULE__{}

  @doc false
  @spec changeset(t(), map(), Leitor.Accounts.Scope.t()) :: Ecto.Changeset.t(t())
  def changeset(attempt, attrs, user_scope) do
    attempt
    |> cast(attrs, [:kind, :content, :result, :duration])
    |> validate_required([:kind, :content, :duration])
    |> validate_length(:content, max: 20_000)
    |> validate_number(:duration, greater_than_or_equal_to: 0, less_than_or_equal_to: 7200)
    |> put_change(:user_id, user_scope.user.id)
  end
end
