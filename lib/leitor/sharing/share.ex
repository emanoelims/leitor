defmodule Leitor.Sharing.Share do
  @moduledoc "A revocable link and general access policy for one private source page."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type :binary_id
  schema "page_shares" do
    field :token, :string, redact: true
    field :link_role, :string, default: "disabled"
    belongs_to :text, Leitor.Library.Text
    timestamps(type: :utc_datetime)
  end

  @typedoc "The stored sharing policy; the token is a bearer capability and must not be logged."
  @type t :: %__MODULE__{}
  @doc "Validates the general link role; ownership and token are assigned by the context."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(share, attrs),
    do: share |> cast(attrs, [:link_role]) |> validate_inclusion(:link_role, ~w(disabled view comment))
end
