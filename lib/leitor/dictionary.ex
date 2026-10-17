defmodule Leitor.Dictionary do
  @moduledoc """
  Looks up a selected English word or short expression for a Portuguese-speaking reader.

  Entries come from the local Wiktionary import (`Leitor.Dictionary.Import`):
  IPA, inflected forms, Brazilian Portuguese translations grouped by sense,
  and English senses. Inflections such as `ran` resolve to their lemma.

  DeepL translates the term using its passage as context. When that
  translation appears in one of the imported sense groups, the group becomes
  the entry's `context` — the meaning in this passage. When Azure Translator is
  configured, up to two bilingual example sentences are added for that
  translation.

  `DEEPL_API_KEY` enables translations (keys ending in `:fx` use the free API
  host); `AZURE_TRANSLATOR_KEY` and, for regional resources,
  `AZURE_TRANSLATOR_REGION` enable examples. Without them the entry comes from
  the local dictionary alone. Only the term and up to 1,000 characters of its
  passage are sent to DeepL; only the term and a translation are sent to Azure.
  Server errors and transport failures are retried twice.
  """

  import Ecto.Query, only: [from: 2]

  alias Leitor.Dictionary.Entry
  alias Leitor.Repo

  @typedoc "A selected word or expression of 1–200 characters."
  @type term_text() :: String.t()

  @typedoc "Portuguese translations of one English sense, labelled by that sense."
  @type group() :: %{sense: String.t(), words: [String.t()]}

  @typedoc "One English sense with an optional usage example."
  @type sense() :: %{definition: String.t(), example: String.t() | nil}

  @typedoc "Translation groups and English senses for one readable part of speech, such as `verb`."
  @type part() :: %{part_of_speech: String.t(), groups: [group()], senses: [sense()]}

  @typedoc "The sense group that contains the contextual translation."
  @type context() :: %{part_of_speech: String.t(), sense: String.t(), words: [String.t()]}

  @typedoc "A sentence split around its highlighted term."
  @type phrase() :: %{prefix: String.t(), term: String.t(), suffix: String.t()}

  @typedoc "An English sentence and its Portuguese translation, with both terms marked."
  @type example() :: %{source: phrase(), target: phrase()}

  @typedoc """
  A lookup result. `translation` is DeepL's contextual rendering; `lemma` and
  `note` explain a resolved inflection (for example `run` and `simple past of run`).
  `parts` exclude the `context` group. Absent data is `nil` or an empty list.
  """
  @type entry() :: %{
          term: term_text(),
          translation: String.t() | nil,
          lemma: String.t() | nil,
          note: String.t() | nil,
          phonetic: String.t() | nil,
          forms: [String.t()],
          context: context() | nil,
          examples: [example()],
          parts: [part()]
        }

  @typedoc "Why a lookup produced no entry."
  @type error() :: :invalid_input | :not_found | :unavailable

  @max_term 200
  @max_context 1000
  @max_words 5
  @max_parts 4
  @max_groups 4
  @max_senses 2
  @max_forms 6
  @max_examples 2
  @max_markdown 3900
  @part_names %{
    "adj" => "adjective",
    "adv" => "adverb",
    "prep" => "preposition",
    "pron" => "pronoun",
    "conj" => "conjunction",
    "det" => "determiner",
    "intj" => "interjection",
    "num" => "numeral",
    "prep_phrase" => "prepositional phrase"
  }

  @doc """
  Looks up `term`, translating it with `context` as surrounding text.

  Surrounding punctuation is removed from `term`. Returns
  `{:error, :invalid_input}` for blank or overlong terms without any request,
  `{:error, :unavailable}` when the dictionary has no entry and DeepL failed,
  and `{:error, :not_found}` when neither knows the term. Examples are optional
  and never decide the result.

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
      alternatives = Task.async(fn -> alternatives(term) end)
      local = local(term)

      build(term, local, Task.await(translation, 20_000), Task.await(alternatives, 20_000))
    end
  end

  @doc ~S"""
  Renders an entry as Markdown for a margin annotation, within 3,900 characters:
  the contextual translation and IPA, a resolved inflection, forms, the sense in
  this passage with examples, then other translations by part of speech.
  Parts without translations show English senses. Dictionary text is escaped
  so it cannot add Markdown structure.

  ## Examples

      iex> Leitor.Dictionary.markdown(%{
      ...>   term: "run",
      ...>   translation: "dirigir",
      ...>   lemma: nil,
      ...>   note: nil,
      ...>   phonetic: "/ɹʌn/",
      ...>   forms: ["ran"],
      ...>   context: %{part_of_speech: "verb", sense: "to be in charge of", words: ["dirigir", "gerir"]},
      ...>   examples: [],
      ...>   parts: [
      ...>     %{part_of_speech: "verb", groups: [%{sense: "to move quickly", words: ["correr"]}], senses: []},
      ...>     %{part_of_speech: "adjective", groups: [], senses: [%{definition: "Melted.", example: nil}]}
      ...>   ]
      ...> })
      "**dirigir** · /ɹʌn/\n\n*Forms:* ran\n\n**In this passage** · *verb* · *to be in charge of*\n\ndirigir, gerir\n\n*verb*\n\n- *to move quickly* → correr\n\n*adjective*\n\n1. Melted."

  """
  @spec markdown(entry()) :: String.t()
  def markdown(entry) do
    lead = entry.translation || first_word(entry) || entry.term

    head =
      Enum.filter(
        [
          Enum.join(["**#{escape(lead)}**" | List.wrap(entry.phonetic && escape(entry.phonetic))], " · "),
          entry.note && "*#{escape(entry.note)}*",
          entry.forms != [] && "*Forms:* " <> Enum.map_join(entry.forms, ", ", &escape/1),
          entry.context && context_markdown(entry.context, entry.examples)
        ],
        &is_binary/1
      )

    entry.parts
    |> Enum.map(&part_markdown/1)
    |> Enum.reduce(Enum.join(head, "\n\n"), fn section, markdown ->
      candidate = markdown <> "\n\n" <> section
      if String.length(candidate) <= @max_markdown, do: candidate, else: markdown
    end)
    |> String.slice(0, @max_markdown)
  end

  @doc """
  Returns the Portuguese meaning to keep in a word jar: the contextual
  translation, else the first dictionary translation, else `""`.

  ## Examples

      iex> Leitor.Dictionary.meaning(%{translation: nil, context: nil, parts: [%{groups: [%{words: ["correr"]}]}]})
      "correr"

  """
  @spec meaning(entry()) :: String.t()
  def meaning(entry), do: entry.translation || first_word(entry) || ""

  @doc """
  Returns the readable part of speech that best describes the entry: the one
  of the passage's meaning, else the first one, else `nil`.
  """
  @spec part_of_speech(entry()) :: String.t() | nil
  def part_of_speech(%{context: %{part_of_speech: part}}), do: part
  def part_of_speech(%{parts: [%{part_of_speech: part} | _]}), do: part
  def part_of_speech(_entry), do: nil

  defp first_word(%{context: %{words: [word | _]}}), do: word

  defp first_word(%{parts: parts}),
    do: Enum.find_value(parts, fn part -> Enum.find_value(part.groups, &List.first(&1.words)) end)

  defp context_markdown(context, examples) do
    title = "**In this passage** · *#{escape(context.part_of_speech)}* · *#{escape(context.sense)}*"
    words = Enum.map_join(context.words, ", ", &escape/1)
    lines = Enum.map(examples, &"- #{phrase(&1.source)} → #{phrase(&1.target)}")
    Enum.join([title, words | if(lines == [], do: [], else: [Enum.join(lines, "\n")])], "\n\n")
  end

  defp part_markdown(%{part_of_speech: part, groups: [_ | _] = groups}) do
    "*#{escape(part)}*\n\n" <> Enum.map_join(groups, "\n", &group_markdown/1)
  end

  defp part_markdown(%{part_of_speech: part, senses: senses}) do
    "*#{escape(part)}*\n\n" <> (senses |> Enum.with_index(1) |> Enum.map_join("\n", &sense_markdown/1))
  end

  defp group_markdown(%{sense: "", words: words}), do: "- " <> Enum.map_join(words, ", ", &escape/1)

  defp group_markdown(%{sense: sense, words: words}),
    do: "- *#{escape(sense)}* → " <> Enum.map_join(words, ", ", &escape/1)

  defp sense_markdown({%{definition: definition, example: nil}, number}), do: "#{number}. #{escape(definition)}"

  defp sense_markdown({%{definition: definition, example: example}, number}),
    do: "#{number}. #{escape(definition)} — *#{escape(example)}*"

  defp phrase(%{prefix: prefix, term: term, suffix: suffix}), do: "#{escape(prefix)}**#{escape(term)}**#{escape(suffix)}"

  @doc """
  Maps a dictionary part of speech to a word-jar category.

  ## Examples

      iex> Leitor.Dictionary.jar_category("adjective")
      "adj"

      iex> Leitor.Dictionary.jar_category("interjection")
      "word"

  """
  @spec jar_category(String.t() | nil) :: String.t()
  def jar_category(part) when part in ["noun", "verb"], do: part
  def jar_category(part) when part in ["adj", "adjective"], do: "adj"
  def jar_category(part) when part in ["adv", "adverb"], do: "adv"
  def jar_category(part) when part in ["pron", "pronoun"], do: "pron"
  def jar_category(part) when part in ["prep", "preposition"], do: "prep"

  def jar_category(part) when part in ["phrase", "prep_phrase", "prepositional phrase", "proverb", "idiom"],
    do: "expression"

  def jar_category(_part), do: "word"

  defp build(term, local, translation_result, alternatives) do
    translation = found(translation_result)
    context = context(local.parts, translation)

    entry =
      Map.merge(local, %{
        term: term,
        translation: translation,
        context: context,
        examples: examples(alternatives, candidates(translation, context)),
        parts: without_context(local.parts, context)
      })

    cond do
      translation != nil or entry.parts != [] or context != nil -> {:ok, entry}
      translation_result == :unavailable -> {:error, :unavailable}
      true -> {:error, :not_found}
    end
  end

  defp found({:ok, value}), do: value
  defp found(_missing), do: nil

  # Local dictionary

  defp local(term) do
    rows = rows(term)

    case redirect(rows) do
      {lemma, note} -> lemma |> rows() |> describe() |> Map.merge(%{lemma: lemma, note: note})
      nil -> rows |> describe() |> Map.merge(%{lemma: nil, note: nil})
    end
  end

  defp rows(term) do
    if length(String.split(term)) > @max_words do
      []
    else
      key = String.downcase(term)
      rows = Repo.all(from(e in Entry, where: e.key == ^key, order_by: e.id))
      exact = Enum.filter(rows, &(&1.word == term))
      if exact == [], do: rows, else: exact
    end
  end

  # An inflection without its own translations shows its first lemma, e.g. ran → run.
  defp redirect(rows) do
    with true <- Enum.all?(rows, &(&1.translations == [])),
         %Entry{form_of: [lemma | _], senses: senses} <- Enum.find(rows, &(&1.form_of != [])) do
      {lemma, Enum.find_value(senses, & &1["gloss"])}
    else
      _no_redirect -> nil
    end
  end

  defp describe(rows) do
    lemmas = Enum.reject(rows, &(&1.form_of != [] and &1.translations == []))
    rows = if lemmas == [], do: rows, else: lemmas

    parts =
      rows
      |> Enum.map(&part_name(&1.part_of_speech))
      |> Enum.uniq()
      |> Enum.map(fn part ->
        entries = Enum.filter(rows, &(part_name(&1.part_of_speech) == part))

        %{
          part_of_speech: part,
          groups:
            entries
            |> Enum.flat_map(& &1.translations)
            |> Enum.map(&%{sense: &1["sense"] || "", words: List.wrap(&1["words"])})
            |> Enum.uniq_by(& &1.sense),
          senses:
            entries
            |> Enum.flat_map(& &1.senses)
            |> Enum.map(&%{definition: &1["gloss"], example: &1["example"]})
            |> Enum.take(@max_senses)
        }
      end)
      |> Enum.reject(&(&1.groups == [] and &1.senses == []))
      |> Enum.take(@max_parts)

    %{
      phonetic: Enum.find_value(rows, & &1.ipa),
      forms: rows |> Enum.flat_map(& &1.forms) |> Enum.uniq() |> Enum.take(@max_forms),
      parts: parts
    }
  end

  defp part_name(part), do: Map.get(@part_names, part, part)

  # The group whose words include the DeepL translation is this passage's meaning.
  defp context(_parts, nil), do: nil

  defp context(parts, translation) do
    target = normalize(translation)

    groups = for part <- parts, group <- part.groups, do: {part.part_of_speech, group}

    Enum.find_value(groups, fn {part, group} ->
      if Enum.any?(group.words, &(normalize(&1) == target)),
        do: %{part_of_speech: part, sense: group.sense, words: group.words}
    end)
  end

  defp without_context(parts, context) do
    parts
    |> Enum.map(fn part ->
      groups =
        Enum.reject(part.groups, &(context && part.part_of_speech == context.part_of_speech && &1.sense == context.sense))

      %{part | groups: Enum.take(groups, @max_groups)}
    end)
    |> Enum.reject(&(&1.groups == [] and &1.senses == []))
  end

  # Matches reflexive variants such as "tornar-se" and "se tornar".
  defp normalize(text) do
    text = text |> String.downcase() |> String.trim()

    case Regex.run(~r/^(.+)-se$/u, text) do
      [_, verb] -> verb
      nil -> String.replace_prefix(text, "se ", "")
    end
  end

  defp candidates(nil, _context), do: []
  defp candidates(translation, nil), do: [normalize(translation)]
  defp candidates(translation, context), do: Enum.uniq([normalize(translation) | Enum.map(context.words, &normalize/1)])

  # DeepL

  defp translate(term, context) do
    case config(:deepl_api_key) do
      key when is_binary(key) and key != "" ->
        [
          method: :post,
          url: deepl_url(key),
          json: %{text: [term], source_lang: "EN", target_lang: "PT-BR", context: context},
          headers: [authorization: "DeepL-Auth-Key #{key}"]
        ]
        |> request()
        |> translation(term)

      _missing ->
        :not_configured
    end
  end

  defp translation({:ok, %Req.Response{status: 200, body: %{"translations" => [%{"text" => text} | _]}}}, term)
       when is_binary(text) do
    text = String.trim(text)
    if text == "" or String.downcase(text) == String.downcase(term), do: :not_found, else: {:ok, text}
  end

  defp translation(_response, _term), do: :unavailable

  defp deepl_url(key) do
    host = if String.ends_with?(key, ":fx"), do: "api-free.deepl.com", else: "api.deepl.com"
    "https://#{host}/v2/translate"
  end

  # Azure Translator examples

  defp alternatives(term) do
    key = config(:azure_translator_key)

    cond do
      key in [nil, ""] -> :not_configured
      length(String.split(term)) > 3 -> :not_found
      true -> key |> azure("lookup", [%{"Text" => term}]) |> lookup_result()
    end
  end

  defp lookup_result(
         {:ok, %Req.Response{status: 200, body: [%{"normalizedSource" => source, "translations" => list} | _]}}
       )
       when is_binary(source) and is_list(list) do
    {:ok, {source, for(%{"normalizedTarget" => target} <- list, is_binary(target), do: target)}}
  end

  defp lookup_result(_response), do: :unavailable

  # Azure only gives examples for translations it lists, so ask for the first
  # one that matches the meaning in this passage.
  defp examples({:ok, {source, targets}}, [_ | _] = candidates) do
    with target when is_binary(target) <- Enum.find(targets, &(normalize(&1) in candidates)),
         {:ok, %Req.Response{status: 200, body: [%{"examples" => list} | _]}} when is_list(list) <-
           azure(config(:azure_translator_key), "examples", [%{"Text" => source, "Translation" => target}]) do
      list |> Enum.flat_map(&example_pair/1) |> Enum.take(@max_examples)
    else
      _missing -> []
    end
  end

  defp examples(_alternatives, _candidates), do: []

  @example_keys ~w(sourcePrefix sourceTerm sourceSuffix targetPrefix targetTerm targetSuffix)

  defp example_pair(example) when is_map(example) do
    ([source_prefix, source_term, source_suffix, target_prefix, target_term, target_suffix] = values) =
      Enum.map(@example_keys, &example[&1])

    if Enum.all?(values, &is_binary/1),
      do: [
        %{
          source: %{prefix: source_prefix, term: source_term, suffix: source_suffix},
          target: %{prefix: target_prefix, term: target_term, suffix: target_suffix}
        }
      ],
      else: []
  end

  defp example_pair(_example), do: []

  defp azure(key, operation, body) do
    region = config(:azure_translator_region)

    request(
      method: :post,
      url: "https://api.cognitive.microsofttranslator.com/dictionary/" <> operation,
      params: ["api-version": "3.0", from: "en", to: "pt"],
      json: body,
      headers:
        [{"ocp-apim-subscription-key", key}] ++
          if(region in [nil, ""], do: [], else: [{"ocp-apim-subscription-region", region}])
    )
  end

  defp escape(text), do: String.replace(text, ~r/[\\`*_\[\]<>#|~]/, "\\\\\\0")

  defp request(options) do
    [retry: &retry?/2, max_retries: 2, retry_delay: &(250 * (&1 + 1)), retry_log_level: false, receive_timeout: 8000]
    |> Keyword.merge(options)
    |> Req.request(config(:req_options, []))
  end

  # Remote services occasionally answer with gateway errors.
  defp retry?(_request, %Req.Response{status: status}), do: status >= 500
  defp retry?(_request, %Req.TransportError{}), do: true
  defp retry?(_request, _exception), do: false

  defp config(key, default \\ nil), do: :leitor |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
end
