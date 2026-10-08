defmodule Leitor.Learning.Practice do
  @moduledoc "Deterministic comparison of a learner's dictation with the original sentence."
  alias Leitor.Library.Reading

  @typedoc "Word alignment and a percentage of correctly recalled original words."
  @type comparison() :: %{
          score: non_neg_integer(),
          correct: non_neg_integer(),
          total: non_neg_integer(),
          parts: [{:eq | :ins | :del, [String.t()]}]
        }

  @doc "Compares normalized words, ignoring capitalization and punctuation. Extra words reduce the score."
  @spec compare(String.t(), String.t()) :: comparison()
  def compare(original, answer) do
    expected = Reading.words(original)
    actual = Reading.words(answer)
    parts = List.myers_difference(expected, actual)
    correct = for({:eq, words} <- parts, reduce: 0, do: (sum -> sum + length(words)))
    total = max(length(expected), length(actual))

    %{
      score: if(total == 0, do: 0, else: round(correct * 100 / total)),
      correct: correct,
      total: length(expected),
      parts: parts
    }
  end
end
