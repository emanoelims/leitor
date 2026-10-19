defmodule Leitor.Sharing.Collaborator do
  @moduledoc "An explicit page permission matched only to a confirmed account email."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type :binary_id
  schema "page_collaborators" do
    field :email, :string
    field :role, :string
    belongs_to :share, Leitor.Sharing.Share
    timestamps(type: :utc_datetime)
  end

  @typedoc "A page collaborator, independent of organization or study roles."
  @type t :: %__MODULE__{}
  @doc "Validates a normalized email and view/comment role, bounded to the account email contract."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:email, :role])
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/)
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:role, ~w(view comment))
    |> unique_constraint([:share_id, :email])
  end
end
