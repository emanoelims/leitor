defmodule Leitor.Accounts.Preferences do
  @moduledoc "Validated account preferences for interface language, AI responses, and Claude models."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :locale, :string, default: "en"
    field :ai_locale, :string, default: "auto"
    field :reading_model, :string, default: "default"
    field :writing_model, :string, default: "default"
    field :image_model, :string, default: "svg"
    field :speech_model, :string, default: "none"
    field :speech_voice, :string, default: "alloy"
  end

  @typedoc "Independent language and model choices, owned by one account."
  @type t() :: %__MODULE__{}
  @typedoc "External preference attributes; unknown and account ownership fields are ignored."
  @type attrs() :: %{optional(String.t() | atom()) => term()}

  @models [
    {"Application default", "default"},
    {"Claude Haiku 5.5", "anthropic:claude-haiku-5-5"},
    {"Claude Sonnet 5.5", "anthropic:claude-sonnet-5-5"},
    {"Claude Opus 5.5", "anthropic:claude-opus-5-5"}
  ]

  @doc "Returns supported languages, using native names so either language is recognizable."
  @spec languages() :: [{String.t(), String.t()}]
  def languages, do: [{"English", "en"}, {"Português (Brasil)", "pt_BR"}]

  @doc "Returns response-language choices, including the existing instruction-dependent behavior."
  @spec response_languages() :: [{String.t(), String.t()}]
  def response_languages, do: [{"Follow the request", "auto"} | languages()]

  @doc "Returns the supported Claude model choices; default uses Haiku on account-authorized requests."
  @spec models() :: [{String.t(), String.t()}]
  def models, do: @models

  @doc "Returns the active SVG mode and provider image models reserved for future image generation."
  @spec image_models() :: [{String.t(), String.t()}]
  def image_models,
    do: [
      {"SVG illustrations (active)", "svg"},
      {"OpenAI GPT Image", "openai:gpt-image-1.5"},
      {"Google Gemini Image", "google:gemini-2.5-flash-image"}
    ]

  @doc "Returns future narration model choices supported by ReqLLM. Narration is not enabled yet."
  @spec speech_models() :: [{String.t(), String.t()}]
  def speech_models,
    do: [
      {"Not configured", "none"},
      {"OpenAI Mini TTS", "openai:gpt-4o-mini-tts"},
      {"ElevenLabs Multilingual", "elevenlabs:eleven_multilingual_v2"}
    ]

  @doc "Constructs preferences through the same validation used by persisted account settings."
  @spec new(attrs()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs), do: %__MODULE__{} |> changeset(attrs) |> apply_action(:validate)

  @doc "Casts and validates language and model choices, preserving omitted existing values."
  @spec changeset(t(), attrs()) :: Ecto.Changeset.t(t())
  def changeset(preferences, attrs) do
    defaults = %__MODULE__{}

    preferences =
      Enum.reduce([:image_model, :speech_model, :speech_voice], preferences, fn field, value ->
        if is_nil(Map.fetch!(value, field)), do: Map.put(value, field, Map.fetch!(defaults, field)), else: value
      end)

    preferences
    |> cast(attrs, [:locale, :ai_locale, :reading_model, :writing_model, :image_model, :speech_model, :speech_voice],
      empty_values: []
    )
    |> validate_required([:locale, :ai_locale, :reading_model, :writing_model])
    |> validate_inclusion(:locale, ~w(en pt_BR))
    |> validate_inclusion(:ai_locale, ~w(auto en pt_BR))
    |> validate_inclusion(:reading_model, Enum.map(@models, &elem(&1, 1)))
    |> validate_inclusion(:writing_model, Enum.map(@models, &elem(&1, 1)))
    |> validate_inclusion(:image_model, Enum.map(image_models(), &elem(&1, 1)))
    |> validate_inclusion(:speech_model, Enum.map(speech_models(), &elem(&1, 1)))
    |> validate_required([:image_model, :speech_model, :speech_voice])
    |> validate_length(:speech_voice, max: 120)
    |> validate_format(:speech_voice, ~r/^[a-zA-Z0-9_.-]+$/)
  end
end
