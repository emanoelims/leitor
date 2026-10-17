defmodule Leitor.Dictionary.Import do
  @moduledoc """
  Imports the English Wiktextract dump published by kaikki.org into
  `dictionary_entries`.

  The source is a JSON Lines file, optionally gzip-compressed, such as
  <https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz>.
  Only English entries are kept, and each is reduced to what the reader shows:
  IPA, inflected forms, lemmas for inflections, up to four English senses with a
  short example, and Brazilian Portuguese translations grouped by sense. Proper
  names, affixes, and symbols are skipped. Content is licensed CC BY-SA by
  Wiktionary contributors.

  An import replaces every existing entry. Lookups during the import may miss
  words that have not been inserted yet.
  """

  alias Leitor.Dictionary.Entry
  alias Leitor.Repo

  @skipped_parts ~w(name prefix suffix infix interfix circumfix symbol character punct)
  # Archaic, regional, or nonstandard forms would mislead a learner.
  @hidden_form_tags ~w(table-tags inflection-template class canonical alternative obsolete archaic dated rare
                       uncommon nonstandard dialectal colloquial informal proscribed misspelling poetic humorous
                       pronunciation-spelling abbreviation second-person Internet)
  @max_senses 4
  @max_example 180
  @max_forms 6
  @max_groups 10
  @max_words 6
  @batch 2000

  @doc """
  Replaces the dictionary from `source`, a local path or an HTTPS URL to a
  `.jsonl` or `.jsonl.gz` dump. A URL is downloaded to a temporary file first,
  which is removed afterwards. Returns the number of imported entries, or an
  error tuple when the download fails.
  """
  @spec import(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def import("https://" <> _ = url) do
    path = Path.join(System.tmp_dir!(), "leitor-dictionary-#{System.unique_integer([:positive])}#{Path.extname(url)}")

    try do
      options = Keyword.get(Application.get_env(:leitor, Leitor.Dictionary, []), :req_options, [])

      case Req.get(url, [into: File.stream!(path), receive_timeout: 120_000, retry: :transient] ++ options) do
        {:ok, %Req.Response{status: 200}} -> {:ok, path |> lines() |> run()}
        {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm(path)
    end
  end

  def import(path), do: {:ok, path |> lines() |> run()}

  @doc """
  Streams the lines of a JSON Lines file, decompressing it when the path ends
  in `.gz`.
  """
  @spec lines(Path.t()) :: Enumerable.t(String.t())
  def lines(path) do
    chunks = File.stream!(path, 1_048_576)
    chunks = if String.ends_with?(path, ".gz"), do: gunzip(chunks), else: chunks

    Stream.transform(
      chunks,
      fn -> "" end,
      fn chunk, rest ->
        [last | complete] = (rest <> chunk) |> String.split("\n") |> Enum.reverse()
        {Enum.reverse(complete), last}
      end,
      fn rest -> {List.wrap(if(rest != "", do: rest)), rest} end,
      fn _rest -> :ok end
    )
  end

  defp gunzip(chunks) do
    Stream.transform(
      chunks,
      fn ->
        zlib = :zlib.open()
        :ok = :zlib.inflateInit(zlib, 31)
        zlib
      end,
      fn chunk, zlib -> {[IO.iodata_to_binary(:zlib.inflate(zlib, chunk))], zlib} end,
      fn zlib ->
        :zlib.inflateEnd(zlib)
        :zlib.close(zlib)
      end
    )
  end

  @doc """
  Replaces all dictionary entries with those decoded from `lines`, inserting
  in batches. Lines that are not valid JSON or not usable English entries are
  skipped. Returns the number of entries inserted.
  """
  @spec run(Enumerable.t(String.t())) :: non_neg_integer()
  def run(lines) do
    Repo.delete_all(Entry, timeout: :infinity, log: false)

    lines
    |> Stream.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, data} -> entry(data)
        {:error, _invalid} -> []
      end
    end)
    |> Stream.chunk_every(@batch)
    |> Enum.reduce(0, fn batch, count ->
      {inserted, _} = Repo.insert_all(Entry, batch, timeout: :infinity, log: false)
      count + inserted
    end)
  end

  @doc """
  Reduces one decoded Wiktextract object to dictionary entry attributes.

  Returns `[]` for non-English entries, skipped parts of speech, and entries
  with neither senses nor translations.

  ## Examples

      iex> Leitor.Dictionary.Import.entry(%{
      ...>   "word" => "Become",
      ...>   "lang_code" => "en",
      ...>   "pos" => "verb",
      ...>   "sounds" => [%{"ipa" => "/bɪˈkʌm/"}],
      ...>   "forms" => [%{"form" => "became", "tags" => ["past"]}, %{"form" => "x", "tags" => ["table-tags"]}],
      ...>   "senses" => [
      ...>     %{
      ...>       "glosses" => ["To begin to be."],
      ...>       "examples" => [%{"text" => "She became a doctor.", "type" => "example"}],
      ...>       "translations" => [%{"code" => "pt", "word" => "tornar-se", "sense" => "to begin to be"}]
      ...>     }
      ...>   ]
      ...> })
      [
        %{
          word: "Become",
          key: "become",
          part_of_speech: "verb",
          ipa: "/bɪˈkʌm/",
          forms: ["became"],
          form_of: [],
          senses: [%{"gloss" => "To begin to be.", "example" => "She became a doctor."}],
          translations: [%{"sense" => "to begin to be", "words" => ["tornar-se"]}]
        }
      ]

      iex> Leitor.Dictionary.Import.entry(%{"word" => "Paris", "lang_code" => "en", "pos" => "name", "senses" => []})
      []

  """
  @spec entry(map()) :: [map()]
  def entry(%{"word" => word, "lang_code" => "en", "pos" => part, "senses" => senses} = data)
      when is_binary(word) and is_binary(part) and is_list(senses) and part not in @skipped_parts do
    attrs = %{
      word: word,
      key: String.downcase(word),
      part_of_speech: part,
      ipa: ipa(data["sounds"]),
      forms: forms(word, data["forms"]),
      form_of: form_of(senses),
      senses: senses(senses),
      translations: translations(data["translations"], senses)
    }

    if attrs.senses == [] and attrs.translations == [], do: [], else: [attrs]
  end

  def entry(_data), do: []

  defp ipa(sounds) when is_list(sounds), do: Enum.find_value(sounds, &(is_map(&1) and text(&1["ipa"])))
  defp ipa(_sounds), do: nil

  defp forms(word, forms) when is_list(forms) do
    for_result =
      for %{"form" => form} = item <- forms,
          is_binary(form),
          form != word,
          String.match?(form, ~r/\p{L}/u),
          not Enum.any?(List.wrap(item["tags"]), &(&1 in @hidden_form_tags)),
          uniq: true do
        form
      end

    Enum.take(for_result, @max_forms)
  end

  defp forms(_word, _forms), do: []

  defp form_of(senses) do
    for %{"form_of" => lemmas} <- senses, %{"word" => lemma} <- List.wrap(lemmas), is_binary(lemma), uniq: true, do: lemma
  end

  defp senses(senses) do
    senses
    |> Enum.flat_map(fn
      %{"glosses" => [_ | _] = glosses} = sense ->
        case text(List.last(glosses)) do
          nil -> []
          gloss -> [%{"gloss" => gloss, "example" => example(sense["examples"])}]
        end

      _sense ->
        []
    end)
    |> Enum.uniq_by(& &1["gloss"])
    |> Enum.take(@max_senses)
  end

  defp example(examples) when is_list(examples) do
    Enum.find_value(examples, fn
      %{"text" => text, "type" => "example"} when is_binary(text) and byte_size(text) <= @max_example -> text(text)
      _example -> nil
    end)
  end

  defp example(_examples), do: nil

  # Wiktextract keeps translations at the entry or sense level. Their own short
  # sense label groups them; words marked only for European Portuguese are dropped.
  defp translations(entry_level, senses) do
    sense_level = for %{"translations" => list} <- senses, is_list(list), item <- list, do: item

    groups =
      for %{"code" => "pt", "word" => word} = item <- List.wrap(entry_level) ++ sense_level,
          text(word),
          not european?(item["tags"]),
          reduce: [] do
        groups ->
          sense = text(item["sense"]) || ""
          words = groups |> List.keyfind(sense, 0, {sense, []}) |> elem(1)
          List.keystore(groups, sense, 0, {sense, Enum.uniq(words ++ [String.trim(word)])})
      end

    groups
    |> Enum.take(@max_groups)
    |> Enum.map(fn {sense, words} -> %{"sense" => sense, "words" => Enum.take(words, @max_words)} end)
  end

  defp european?(tags), do: "Portugal" in List.wrap(tags) and "Brazil" not in List.wrap(tags)

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp text(_value), do: nil
end
