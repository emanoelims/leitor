defmodule Leitor.Dictionary do
  @moduledoc """
  Looks up a selected English word or short expression in complementary sources.

  DeepL supplies a Brazilian Portuguese translation that uses the surrounding
  passage as context, so polysemous words follow their meaning in the text.
  Wiktionary's REST API supplies English senses and examples grouped by part of
  speech. The Free Dictionary API (dictionaryapi.dev), whose availability is
  intermittent, adds phonetics and pronunciation audio when it answers. The
  requests run concurrently; the entry keeps whatever was found.

  DeepL requires `DEEPL_API_KEY`; keys ending in `:fx` use the free API host.
  Without a key the lookup still returns dictionary data. Only the selected term
  and up to 1,000 characters of its passage are sent to DeepL; only the term is
  sent to the dictionaries. Server errors and transport failures are retried twice.
  """

  @typedoc "A selected word or expression of 1–200 characters."
  @type term_text() :: String.t()

  @typedoc "One plain-text sense of a part of speech, with an optional usage example."
  @type sense() :: %{definition: String.t(), example: String.t() | nil}

  @typedoc "Dictionary senses grouped by a lowercase part of speech, such as `noun` or `phrasal verb`."
  @type meaning() :: %{part_of_speech: String.t(), senses: [sense()]}

  @typedoc """
  A lookup result. `translation` is the contextual Brazilian Portuguese rendering;
  `audio` is an HTTPS pronunciation URL. Absent data is `nil` or an empty list.
  """
  @type entry() :: %{
          term: term_text(),
          translation: String.t() | nil,
          phonetic: String.t() | nil,
          audio: String.t() | nil,
          meanings: [meaning()]
        }

  @typedoc "Why a lookup produced no entry."
  @type error() :: :invalid_input | :not_found | :unavailable

  @max_term 200
  @max_context 1000
  @max_meanings 4
  @max_senses 3
  @user_agent "Leitor/#{Mix.Project.config()[:version]} (https://github.com/emanoelims/leitor)"

  @doc """
  Looks up `term`, translating it with `context` as surrounding text.

  Surrounding punctuation is removed from `term`. Returns
  `{:error, :invalid_input}` for blank or overlong terms without any request.
  A translation identical to the term is treated as missing. Returns
  `{:error, :not_found}` when no source knows the term, and
  `{:error, :unavailable}` when nothing was found because a source failed.
  Pronunciation never decides the result.

  ## Examples

      iex> Leitor.Dictionary.lookup(" — ", "")
      {:error, :invalid_input}

  """
  @spec lookup(term_text(), String.t()) :: {:ok, entry()} | {:error, error()}
  def lookup(term, context) when is_binary(term) and is_binary(context) do
    term = String.replace(term, ~r/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/u, "")

    if term == "" or String.length(term) > @max_term do
      {:error, :invalid_input}
    else
      translation = Task.async(fn -> translate(term, String.slice(context, 0, @max_context)) end)
      definitions = Task.async(fn -> define(term) end)
      pronunciation = Task.async(fn -> pronounce(term) end)

      build(term, Task.await(translation, 15_000), Task.await(definitions, 15_000), Task.await(pronunciation, 15_000))
    end
  end

  @doc ~S"""
  Renders an entry as Markdown for a margin annotation: the contextual
  translation and phonetics first, then numbered senses by part of speech.
  Source text is escaped so dictionary content cannot add Markdown structure.

  ## Examples

      iex> Leitor.Dictionary.markdown(%{
      ...>   term: "run",
      ...>   translation: "dirigir",
      ...>   phonetic: "/ɹʌn/",
      ...>   audio: nil,
      ...>   meanings: [%{part_of_speech: "verb", senses: [%{definition: "To manage.", example: "Run a shop."}]}]
      ...> })
      "**dirigir** · /ɹʌn/\n\n*verb*\n\n1. To manage. — *Run a shop.*"

  """
  @spec markdown(entry()) :: String.t()
  def markdown(%{term: term, translation: translation, phonetic: phonetic, meanings: meanings}) do
    heading =
      [translation && "**#{escape(translation)}**", phonetic && escape(phonetic)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    sections =
      Enum.map(meanings, fn %{part_of_speech: part, senses: senses} ->
        items = senses |> Enum.with_index(1) |> Enum.map_join("\n", &sense_markdown/1)
        "*#{escape(part)}*\n\n#{items}"
      end)

    Enum.join([if(heading == "", do: "**#{escape(term)}**", else: heading) | sections], "\n\n")
  end

  defp sense_markdown({%{definition: definition, example: nil}, number}), do: "#{number}. #{escape(definition)}"

  defp sense_markdown({%{definition: definition, example: example}, number}),
    do: "#{number}. #{escape(definition)} — *#{escape(example)}*"

  @doc """
  Maps a dictionary part of speech to a word-jar category.

  ## Examples

      iex> Leitor.Dictionary.jar_category("adjective")
      "adj"

      iex> Leitor.Dictionary.jar_category("interjection")
      "word"

  """
  @spec jar_category(String.t() | nil) :: String.t()
  def jar_category(part_of_speech) when part_of_speech in ["noun", "proper noun"], do: "noun"
  def jar_category(part_of_speech) when part_of_speech in ["verb", "phrasal verb"], do: "verb"
  def jar_category(part_of_speech) when part_of_speech in ["idiom", "phrase", "proverb"], do: "expression"
  def jar_category("adjective"), do: "adj"
  def jar_category("adverb"), do: "adv"
  def jar_category("pronoun"), do: "pron"
  def jar_category("preposition"), do: "prep"
  def jar_category(_part_of_speech), do: "word"

  defp build(term, translation, definitions, pronunciation) do
    entry =
      Map.merge(
        %{term: term, translation: found(translation), meanings: found(definitions) || []},
        pronunciation
      )

    cond do
      entry.translation || entry.meanings != [] -> {:ok, entry}
      :unavailable in [translation, definitions] -> {:error, :unavailable}
      true -> {:error, :not_found}
    end
  end

  defp found({:ok, value}), do: value
  defp found(_missing), do: nil

  defp translate(term, context) do
    case config(:deepl_api_key) do
      key when is_binary(key) and key != "" ->
        body = %{text: [term], source_lang: "EN", target_lang: "PT-BR", context: context}

        [
          method: :post,
          url: deepl_url(key),
          json: body,
          headers: [authorization: "DeepL-Auth-Key #{key}"]
        ]
        |> request()
        |> then(&translation(term, &1))

      _missing ->
        :not_configured
    end
  end

  defp translation(term, {:ok, %Req.Response{status: 200, body: %{"translations" => [%{"text" => text} | _]}}})
       when is_binary(text) do
    text = String.trim(text)
    if text == "" or String.downcase(text) == String.downcase(term), do: :not_found, else: {:ok, text}
  end

  defp translation(_term, _response), do: :unavailable

  defp deepl_url(key) do
    host = if String.ends_with?(key, ":fx"), do: "api-free.deepl.com", else: "api.deepl.com"
    "https://#{host}/v2/translate"
  end

  defp define(term) do
    word = String.downcase(term)

    if length(String.split(word)) > 3 do
      :not_found
    else
      path = word |> String.replace(" ", "_") |> URI.encode(&URI.char_unreserved?/1)

      [method: :get, url: "https://en.wiktionary.org/api/rest_v1/page/definition/" <> path]
      |> request()
      |> definitions()
    end
  end

  defp definitions({:ok, %Req.Response{status: 200, body: %{} = languages}}) do
    sections = if is_list(languages["en"]), do: languages["en"], else: []

    meanings =
      for %{"partOfSpeech" => part, "definitions" => senses} = section <- sections,
          is_binary(part) and is_list(senses) and Map.get(section, "language", "English") == "English" do
        %{part_of_speech: String.downcase(part), senses: senses(senses)}
      end

    case merge_meanings(meanings) do
      [] -> :not_found
      meanings -> {:ok, meanings}
    end
  end

  defp definitions({:ok, %Req.Response{status: 404}}), do: :not_found
  defp definitions(_response), do: :unavailable

  # Wiktionary repeats a parent example under nested senses; show each example once.
  defp senses(senses) do
    senses
    |> Enum.flat_map(fn
      %{"definition" => html} = sense when is_binary(html) -> [%{definition: plain(html), example: example(sense)}]
      _sense -> []
    end)
    |> Enum.reject(&(&1.definition == ""))
    |> Enum.map_reduce(MapSet.new(), fn sense, seen ->
      if MapSet.member?(seen, sense.example),
        do: {%{sense | example: nil}, seen},
        else: {sense, MapSet.put(seen, sense.example)}
    end)
    |> elem(0)
  end

  defp example(sense) do
    examples = for(%{"example" => html} <- List.wrap(sense["parsedExamples"]), do: html) ++ List.wrap(sense["examples"])
    Enum.find_value(examples, &(is_binary(&1) and present(plain(&1))))
  end

  # Wiktionary returns trusted-structure HTML fragments; keep the top-level sense text only.
  # The result is plain text and is still escaped when rendered.
  defp plain(html) do
    html
    |> String.split(~r/<(ol|ul|dl)\b/, parts: 2)
    |> hd()
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~r/&(#\d+|#x[0-9a-f]+|amp|lt|gt|quot|apos|nbsp);/i, &entity/1)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp entity(entity) do
    case String.downcase(entity) do
      "&amp;" -> "&"
      "&lt;" -> "<"
      "&gt;" -> ">"
      "&quot;" -> ~s(")
      "&apos;" -> "'"
      "&nbsp;" -> " "
      "&#x" <> hex -> codepoint(Integer.parse(String.trim_trailing(hex, ";"), 16))
      "&#" <> decimal -> codepoint(Integer.parse(String.trim_trailing(decimal, ";")))
    end
  end

  defp codepoint({code, ""}) when code in 32..0x10FFFF and code not in 0xD800..0xDFFF, do: <<code::utf8>>
  defp codepoint(_invalid), do: ""

  defp merge_meanings(meanings) do
    meanings
    |> Enum.map(& &1.part_of_speech)
    |> Enum.uniq()
    |> Enum.map(fn part ->
      senses = meanings |> Enum.filter(&(&1.part_of_speech == part)) |> Enum.flat_map(& &1.senses)
      %{part_of_speech: part, senses: Enum.take(senses, @max_senses)}
    end)
    |> Enum.reject(&(&1.senses == []))
    |> Enum.take(@max_meanings)
  end

  defp pronounce(term) do
    word = String.downcase(term)

    with false <- String.contains?(word, " "),
         {:ok, %Req.Response{status: 200, body: [_ | _] = entries}} <-
           request(method: :get, url: "https://api.dictionaryapi.dev/api/v2/entries/en/" <> URI.encode_www_form(word)) do
      %{phonetic: phonetic(entries), audio: audio(entries)}
    else
      _missing -> %{phonetic: nil, audio: nil}
    end
  end

  defp phonetic(entries) do
    Enum.find_value(entries, fn entry ->
      is_map(entry) and
        (present(entry["phonetic"]) ||
           Enum.find_value(List.wrap(entry["phonetics"]), &(is_map(&1) and present(&1["text"]))))
    end) || nil
  end

  defp audio(entries) do
    urls =
      for %{} = entry <- entries,
          %{"audio" => "https://" <> _ = url} <- List.wrap(entry["phonetics"]),
          do: url

    Enum.find(urls, &String.ends_with?(&1, "-us.mp3")) || List.first(urls)
  end

  defp escape(text), do: String.replace(text, ~r/[\\`*_\[\]<>#|~]/, "\\\\\\0")

  defp present(text) when is_binary(text) and text != "", do: text
  defp present(_text), do: nil

  defp request(options) do
    [
      retry: &retry?/2,
      max_retries: 2,
      retry_delay: &(250 * (&1 + 1)),
      retry_log_level: false,
      receive_timeout: 8000,
      user_agent: @user_agent
    ]
    |> Keyword.merge(options)
    |> Req.request(config(:req_options, []))
  end

  # Public dictionaries intermittently answer with gateway errors such as 522.
  defp retry?(_request, %Req.Response{status: status}), do: status >= 500
  defp retry?(_request, %Req.TransportError{}), do: true
  defp retry?(_request, _exception), do: false

  defp config(key, default \\ nil), do: :leitor |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
end
