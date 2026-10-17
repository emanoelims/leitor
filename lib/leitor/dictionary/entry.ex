defmodule Leitor.Dictionary.Entry do
  @moduledoc """
  One English part-of-speech entry imported from Wiktextract (kaikki.org).

  `key` is the lowercase lookup form of `word`. `senses` hold English glosses
  with an optional example (`"gloss"`, `"example"`); `translations` hold
  Brazilian Portuguese translations grouped by the sense they translate
  (`"sense"`, `"words"`). `form_of` names lemmas when the word is an inflection,
  such as `ran` for `run`. Entries are shared reference data, not user records.
  """
  use Ecto.Schema

  schema "dictionary_entries" do
    field :word, :string
    field :key, :string
    field :part_of_speech, :string
    field :ipa, :string
    field :forms, {:array, :string}, default: []
    field :form_of, {:array, :string}, default: []
    field :senses, {:array, :map}, default: []
    field :translations, {:array, :map}, default: []
  end

  @typedoc "An imported dictionary entry."
  @type t() :: %__MODULE__{
          id: pos_integer() | nil,
          word: String.t() | nil,
          key: String.t() | nil,
          part_of_speech: String.t() | nil,
          ipa: String.t() | nil,
          forms: [String.t()],
          form_of: [String.t()],
          senses: [%{optional(String.t()) => String.t() | nil}],
          translations: [%{optional(String.t()) => String.t() | [String.t()]}]
        }
end
