defmodule Leitor.Dictionary.Card do
  @moduledoc """
  A generated dictionary card, cached by a hash of the model, prompt version,
  selection, and marked paragraph. Repeating the same lookup reuses the card
  instead of calling the model again. Cards hold no user data.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  schema "dictionary_cards" do
    field :key, :string
    field :model, :string
    field :card, :map
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @typedoc "A cached dictionary card."
  @type t() :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          key: String.t() | nil,
          model: String.t() | nil,
          card: Leitor.Dictionary.card() | nil,
          inserted_at: DateTime.t() | nil
        }
end
