defmodule Leitor.Generations.Generation do
  @moduledoc "An account-owned durable figure generation and its private recovery snapshot."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  @derive {Inspect, only: [:id, :user_id, :status, :stage]}
  schema "page_generations" do
    belongs_to :user, Leitor.Accounts.User
    belongs_to :text, Leitor.Library.Text
    embeds_one :request, Leitor.Generations.Request, on_replace: :update
    field :client_id, :string
    field :revision_id, Ecto.UUID
    field :lease_id, Ecto.UUID
    field :expires_at, :utc_datetime
    field :status, :string, default: "running"
    field :stage, :string, default: "building"
    field :markdown, :string
    field :error, :string
    field :dismissed, :boolean, default: false
    timestamps(type: :utc_datetime)
  end

  @typedoc "A persisted attempt; only independently accepted Markdown becomes a ready result."
  @type t :: %__MODULE__{}

  @doc "Validates the request snapshot; ownership, status and authorization are assigned by the context."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(generation, attrs) do
    generation
    |> cast(attrs, [:client_id])
    |> cast_embed(:request, required: true)
    |> validate_required([:client_id])
    |> validate_length(:client_id, max: 64)
  end
end
