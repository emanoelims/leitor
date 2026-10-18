defmodule Leitor.AI.Credential do
  @moduledoc "An account-owned encrypted provider key. Plaintext input is virtual and redacted."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "ai_credentials" do
    field :provider, :string
    field :api_key, :string, virtual: true, redact: true
    field :encrypted_key, :binary, redact: true
    field :hint, :string
    belongs_to :user, Leitor.Accounts.User
    timestamps(type: :utc_datetime)
  end

  @typedoc "A stored credential; encrypted data and virtual plaintext are redacted."
  @type t :: %__MODULE__{}
  @typedoc "Untrusted provider and plaintext credential input. Ownership is assigned by the context."
  @type attrs :: %{optional(String.t() | atom()) => term()}

  @doc "Returns provider identifiers supported by the app's text and future media configuration."
  @spec providers() :: [{String.t(), String.t()}]
  def providers,
    do: [
      {"Anthropic", "anthropic"},
      {"OpenAI", "openai"},
      {"Google", "google"},
      {"ElevenLabs", "elevenlabs"},
      {"Groq", "groq"}
    ]

  @doc "Validates key input without casting ownership, encrypted data, or identifiers."
  @spec changeset(t(), attrs()) :: Ecto.Changeset.t(t())
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:provider, :api_key])
    |> update_change(:api_key, &String.trim/1)
    |> validate_required([:provider, :api_key])
    |> validate_inclusion(:provider, Enum.map(providers(), &elem(&1, 1)))
    |> validate_length(:api_key, min: 12, max: 500)
    |> validate_format(:api_key, ~r/^[\x21-\x7e]+$/)
    |> unique_constraint([:user_id, :provider])
  end
end
