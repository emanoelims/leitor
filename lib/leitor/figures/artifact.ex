defmodule Leitor.Figures.Artifact do
  @moduledoc "An immutable account-owned program revision, its source, execution evidence and optional reviewed bundle."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "figure_artifacts" do
    belongs_to :user, Leitor.Accounts.User, type: :binary_id
    belongs_to :parent, __MODULE__, type: :binary_id
    field :title, :string
    field :caption, :string
    field :model, :string
    field :source, :map
    field :report, :map
    field :bundle, :binary
    field :style, :string
    field :preview, :binary
    field :digest, :string
    field :status, :string
    timestamps(type: :utc_datetime)
  end

  @typedoc "A private generated revision; only ready revisions may execute in a reader."
  @type t :: %__MODULE__{}
end
