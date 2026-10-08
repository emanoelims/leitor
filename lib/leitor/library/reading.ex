defmodule Leitor.Library.Reading do
  @moduledoc "Sentence preparation and the editorial reading sample, independent of persistence."

  @external_resource "priv/content/bohemia.json"
  @sample "priv/content/bohemia.json" |> File.read!() |> Jason.decode!()
  @typedoc "A prepared sentence with optional editorial language annotations."
  @type sentence() :: map()

  @doc "Returns the five annotated sentences from the public-domain reading sample."
  @spec sample() :: [sentence()]
  def sample do
    Enum.map(@sample, fn sentence ->
      tokens = Enum.map(sentence["tokens"], &token/1)
      body = tokens |> Enum.map_join(" ", & &1.word) |> String.replace(~r/\s+([.,!?;:])/, "\\1")

      %{
        body: body,
        tokens: tokens,
        translation: sentence["translation"],
        tense: sentence["tense"],
        focus: focus(sentence["focus"]),
        chunks: sentence["chunks"]
      }
    end)
  end

  @typedoc "English source material before sentence preparation."
  @type body() :: String.t()
  @typedoc "A normalized vocabulary word used for comparison."
  @type word() :: String.t()

  @doc "Splits plain English text into bounded sentences, preserving punctuation."
  @spec prepare(body()) :: [sentence()]
  def prepare(body) do
    body
    |> String.split(~r/(?<=[.!?])\s+|\n\s*\n/, trim: true)
    |> Enum.flat_map(&chunk/1)
    |> Enum.map(fn text ->
      tokens =
        ~r/[\p{L}\p{N}]+(?:['’\-][\p{L}]+)*|[^\s\p{L}\p{N}]/u
        |> Regex.scan(text)
        |> Enum.map(fn [word] -> %{word: word, category: "word", ipa: "", meaning: "", definition: "", note: ""} end)

      %{body: text, tokens: tokens, translation: nil, tense: "Your text", focus: nil, chunks: []}
    end)
  end

  @doc "Returns normalized word tokens for comparisons and vocabulary identity."
  @spec words(body()) :: [word()]
  def words(text), do: ~r/[\p{L}\p{N}]+(?:['’][\p{L}]+)*/u |> Regex.scan(String.downcase(text)) |> List.flatten()

  defp chunk(text) do
    if String.length(text) > 3000,
      do: text |> String.graphemes() |> Enum.chunk_every(3000) |> Enum.map(&Enum.join/1),
      else: [String.trim(text)]
  end

  defp token([word, nil]), do: %{word: word, category: "punctuation", ipa: "", meaning: "", definition: "", note: ""}

  defp token([word, category, ipa, meaning, definition, _note]),
    do: %{word: word, category: category, ipa: ipa, meaning: meaning, definition: definition, note: definition}

  defp focus(nil), do: nil

  defp focus(%{"title" => title, "body" => body, "pattern" => pattern}) do
    %{title: title, body: body, pattern: pattern}
  end
end
