defmodule Leitor.Language.AnswerStream do
  @moduledoc "Provisional answer previews from the flat JSON object emitted by the reading tutor. Final schema validation stays with ReqLLM."

  @doc """
  Extracts the available `answer` string from up to 128,000 bytes of incomplete
  JSON. Incomplete escapes and Unicode surrogate pairs are withheld until the
  next fragment. Metadata fields are never returned. This is a display preview,
  not a JSON repair or validation API; malformed input may return an empty string.
  """
  @spec preview(String.t()) :: String.t()
  def preview(json) when byte_size(json) <= 128_000 do
    case Regex.run(~r/(?:\A\s*\{|,)\s*"answer"\s*:\s*"((?:\\.|[^"\\])*)/s, json, capture: :all_but_first) do
      [answer] -> decode_prefix(answer, 12)
      _ -> ""
    end
  end

  def preview(_json), do: ""

  defp decode_prefix(_answer, 0), do: ""

  defp decode_prefix(answer, attempts) do
    case Jason.decode("\"" <> answer <> "\"") do
      {:ok, text} -> text
      {:error, _} -> decode_prefix(String.slice(answer, 0, max(0, String.length(answer) - 1)), attempts - 1)
    end
  end
end
