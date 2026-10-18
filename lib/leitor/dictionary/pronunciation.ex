defmodule Leitor.Dictionary.Pronunciation do
  @moduledoc """
  Respells General American IPA with Brazilian Portuguese spelling, so a reader
  can approximate an English word without knowing IPA.

  Syllables are separated by hyphens and the stressed one is written in
  capitals. Reduced vowels (schwa) become `â`, `h` becomes `rr` (as in
  "carro"), `sh` becomes `ch`, and an American flapped `t`/`d` between vowels
  becomes `r` (as in "caro"). Sounds Portuguese lacks, such as `th`, keep their
  English spelling. The result is a deterministic hint derived only from the
  IPA; it never influences the meaning shown to the reader.
  """

  @vowels %{
    "eɪ" => "ei",
    "aɪ" => "ai",
    "aʊ" => "au",
    "ɔɪ" => "ói",
    "oʊ" => "ou",
    "əʊ" => "ou",
    "ɝ" => "âr",
    "ɚ" => "âr",
    "ɜ" => "â",
    "iː" => "i",
    "i" => "i",
    "ɪ" => "i",
    "ɨ" => "i",
    "ᵻ" => "i",
    "e" => "é",
    "ɛ" => "é",
    "æ" => "é",
    "ɑː" => "á",
    "ɑ" => "á",
    "ɒ" => "á",
    "a" => "á",
    "ɔː" => "ó",
    "ɔ" => "ó",
    "o" => "ô",
    "uː" => "u",
    "u" => "u",
    "ʊ" => "u",
    "ʌ" => "â",
    "ə" => "â",
    "ɵ" => "â"
  }

  @consonants %{
    "tʃ" => "tch",
    "dʒ" => "dj",
    "θ" => "th",
    "ð" => "th",
    "ʃ" => "ch",
    "ʒ" => "j",
    "ŋ" => "ng",
    "ɾ" => "r",
    "r" => "r",
    "j" => "i",
    "w" => "u",
    "h" => "rr",
    "x" => "rr",
    "ʔ" => "t",
    "ɫ" => "l",
    "l" => "l",
    "m" => "m",
    "n" => "n",
    "p" => "p",
    "b" => "b",
    "t" => "t",
    "d" => "d",
    "k" => "k",
    "ɡ" => "g",
    "f" => "f",
    "v" => "v",
    "s" => "s",
    "z" => "z"
  }

  @onsets ~w(pl pr bl br tr dr kl kr ɡl ɡr fl fr θr ʃr sp st sk sm sn sl sw tw kw dw ɡw pj bj kj fj mj vj hj nj lj tj dj
             spr str skr spl skw)
  @symbols Enum.sort_by(Map.keys(@vowels) ++ Map.keys(@consonants), &String.length/1, :desc)

  @typedoc "A pronunciation hint such as `KÂMF-târ-bâl`."
  @type hint() :: String.t()

  @doc """
  Respells an IPA transcription (with or without slashes). Each word of a
  multiword transcription is respelled separately. Unknown symbols are ignored.

  ## Examples

      iex> Leitor.Dictionary.Pronunciation.respell("/ˈkʌmftərbəl/")
      "KÂMF-târ-bâl"

      iex> Leitor.Dictionary.Pronunciation.respell("ˈwɔtər")
      "UÓ-râr"

      iex> Leitor.Dictionary.Pronunciation.respell("ˈhɑɡzˌhɛd")
      "RRÁGZ-rréd"

      iex> Leitor.Dictionary.Pronunciation.respell("θɔt")
      "THÓT"

      iex> Leitor.Dictionary.Pronunciation.respell("ɪn wɑnt ʌv")
      "in uánt âv"

      iex> Leitor.Dictionary.Pronunciation.respell("")
      ""

  """
  @spec respell(String.t()) :: hint()
  def respell(ipa) when is_binary(ipa) do
    words = ipa |> String.trim() |> String.trim("/") |> String.trim("[") |> String.trim("]") |> String.split()
    Enum.map_join(words, " ", &word(&1, length(words) > 1))
  end

  defp word(word, multiword?) do
    sylls = word |> tokens() |> syllables()

    parts =
      sylls
      |> Enum.with_index()
      |> Enum.map(fn {{stressed, _phonemes}, k} ->
        phonemes = flap(sylls, k)
        text = cross_syllable_s(sylls, k, phonemes) <> spell(phonemes)
        if stressed and length(sylls) > 1, do: String.upcase(text), else: text
      end)

    joined = Enum.join(parts, "-")
    if length(sylls) == 1 and not multiword?, do: String.upcase(joined), else: joined
  end

  defp tokens(word) do
    word
    |> String.replace(~r/[ˑ̯̩̥ʰ̃ʲ]/u, "")
    |> String.replace("ɹ", "r")
    |> String.replace("g", "ɡ")
    |> then(&Regex.replace(~r/([tdkɡpbszʃ])([nlm])(?=[^aeiouɑɒɔəɛɪʊʌæɜɝɚ]|$)/u, &1, "\\1ə\\2"))
    |> tokenize([])
  end

  defp tokenize("", acc), do: Enum.reverse(acc)

  defp tokenize(<<mark::utf8, rest::binary>>, acc) when mark in [?ˈ, ?ˌ, ?.], do: tokenize(rest, [<<mark::utf8>> | acc])

  defp tokenize(text, acc) do
    case Enum.find(@symbols, &String.starts_with?(text, &1)) do
      nil ->
        {_skipped, rest} = String.next_codepoint(text)
        tokenize(rest, acc)

      symbol ->
        tokenize(binary_part(text, byte_size(symbol), byte_size(text) - byte_size(symbol)), [symbol | acc])
    end
  end

  # Splits phonemes into {stressed?, phonemes} syllables with a maximal-onset rule;
  # explicit stress or syllable marks in the IPA win.
  defp syllables(tokens) do
    {phonemes, marks} =
      Enum.reduce(tokens, {[], %{}}, fn
        mark, {phonemes, marks} when mark in ["ˈ", "ˌ", "."] -> {phonemes, Map.put(marks, length(phonemes), mark)}
        phoneme, {phonemes, marks} -> {phonemes ++ [phoneme], marks}
      end)

    nuclei = for {phoneme, i} <- Enum.with_index(phonemes), Map.has_key?(@vowels, phoneme), do: i

    case nuclei do
      [] ->
        [{true, phonemes}]

      _ ->
        starts = [0 | nuclei |> Enum.zip(tl(nuclei)) |> Enum.map(&boundary(&1, phonemes, marks))]
        bounds = Enum.zip(starts, tl(starts) ++ [length(phonemes)])
        sylls = Enum.map(bounds, fn {first, last} -> {marks[first] == "ˈ", Enum.slice(phonemes, first, last - first)} end)

        case sylls do
          [{_stressed, only}] -> [{true, only}]
          many -> many
        end
    end
  end

  defp boundary({a, b}, phonemes, marks) do
    case Enum.find((a + 1)..b//1, &Map.has_key?(marks, &1)) do
      nil when b == a + 1 ->
        b

      nil ->
        cluster = Enum.slice(phonemes, (a + 1)..(b - 1)//1)
        b - onset_length(cluster)

      explicit ->
        explicit
    end
  end

  defp onset_length(cluster) do
    Enum.find([3, 2], 1, &(length(cluster) >= &1 and Enum.join(Enum.take(cluster, -&1)) in @onsets))
  end

  # American English flap: t/d after a vowel (or t after r, as in "party") and before an unstressed vowel.
  defp flap(sylls, k) do
    {stressed, phonemes} = Enum.at(sylls, k)

    with false <- k == 0 or stressed,
         [first, second | rest] when first in ["t", "d"] <- phonemes,
         true <- Map.has_key?(@vowels, second),
         {_stress, [_ | _] = previous} <- Enum.at(sylls, k - 1),
         true <- Map.has_key?(@vowels, List.last(previous)) or (List.last(previous) == "r" and first == "t") do
      ["ɾ", second | rest]
    else
      _not_flapped -> phonemes
    end
  end

  # Keeps Portuguese from voicing an s that starts a syllable after a vowel ("ssâ" in plasticity).
  defp cross_syllable_s(sylls, k, [first, second | _]) when k > 0 and first == "s" do
    {_stress, previous} = Enum.at(sylls, k - 1)
    if Map.has_key?(@vowels, second) and previous != [] and Map.has_key?(@vowels, List.last(previous)), do: "s", else: ""
  end

  defp cross_syllable_s(_sylls, _k, _phonemes), do: ""

  defp spell(phonemes) do
    phonemes
    |> Enum.with_index()
    |> Enum.map_join(fn {phoneme, i} ->
      previous = if i > 0, do: Enum.at(phonemes, i - 1)
      following = Enum.at(phonemes, i + 1)

      cond do
        Map.has_key?(@vowels, phoneme) -> @vowels[phoneme]
        phoneme == "ɡ" and front_vowel?(following) -> "gu"
        phoneme == "s" and vowel?(previous) and vowel?(following) -> "ss"
        true -> @consonants[phoneme]
      end
    end)
  end

  defp vowel?(phoneme), do: is_binary(phoneme) and Map.has_key?(@vowels, phoneme)
  defp front_vowel?(phoneme), do: vowel?(phoneme) and String.first(@vowels[phoneme]) in ["i", "e", "é"]
end
