defmodule Leitor.Language.AnswerStream do
  @moduledoc "Provisional answer previews from the flat JSON object emitted by the reading tutor. Final schema validation stays with ReqLLM."

  @doc """
  Extracts the available string of `field` (by default `answer`) from up to
  128,000 bytes of incomplete JSON. Incomplete escapes and Unicode surrogate
  pairs are withheld until the next fragment. Other fields are never returned.
  This is a display preview, not a JSON repair or validation API; malformed
  input may return an empty string.

  ## Examples

      iex> Leitor.Language.AnswerStream.preview(~s({"answer": "Very go))
      "Very go"

      iex> Leitor.Language.AnswerStream.preview(~s({"meaning": "conseguir", "headword": "pu), "meaning")
      "conseguir"

  """
  @spec preview(String.t()) :: String.t()
  @spec preview(String.t(), String.t()) :: String.t()
  def preview(json, field \\ "answer")

  def preview(json, field) when byte_size(json) <= 128_000 and is_binary(field) do
    pattern = ~r/(?:\A\s*\{|,)\s*"#{Regex.escape(field)}"\s*:\s*"((?:\\.|[^"\\])*)/s

    case Regex.run(pattern, json, capture: :all_but_first) do
      [answer] -> decode_prefix(answer, 12)
      _ -> ""
    end
  end

  def preview(_json, _field), do: ""

  defp decode_prefix(_answer, 0), do: ""

  defp decode_prefix(answer, attempts) do
    case Jason.decode("\"" <> answer <> "\"") do
      {:ok, text} -> text
      {:error, _} -> decode_prefix(String.slice(answer, 0, max(0, String.length(answer) - 1)), attempts - 1)
    end
  end
end
