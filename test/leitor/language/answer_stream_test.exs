defmodule Leitor.Language.AnswerStreamTest do
  use ExUnit.Case, async: true

  alias Leitor.Language.AnswerStream

  test "previews only the answer, with escaped quotes, line breaks and any field order" do
    answer = "**A word.**\nA quote: \"yes\", and a backslash \\."
    json = Jason.encode!(%{answer: answer, category: "noun", meaning: "Never show this metadata"})
    assert AnswerStream.preview(json) == answer
    assert AnswerStream.preview(~S({"meaning":"Not this","answer":"A partial)) == "A partial"
    assert AnswerStream.preview(~S({"answer":"One\nTwo\")) == "One\nTwo\""
    assert AnswerStream.preview("{\"answer\":\"One\\") == "One"
    assert AnswerStream.preview(~S({"meaning":"\"answer\": \"not an answer\""})) == ""
  end

  test "withholds incomplete Unicode escapes, then decodes complete surrogate pairs" do
    for tail <- ["\\u", "\\u0", "\\u00", "\\u00e", "\\uD83D", "\\uD83D\\u", "\\uD83D\\uDE0"] do
      assert AnswerStream.preview("{\"answer\":\"Hi " <> tail) == "Hi "
    end

    assert AnswerStream.preview(~S({"answer":"Caf\u00e9)) == "Café"
    assert AnswerStream.preview(~S({"answer":"Hi \uD83D\uDE00)) == "Hi 😀"
  end

  test "each complete UTF-8 prefix remains a prefix of the final answer" do
    answer = "Café, \"a word\", a line\nnext line \\ and 😀"
    json = Jason.encode!(%{answer: answer, category: "noun", meaning: "significado"})

    for n <- 0..String.length(json) do
      assert String.starts_with?(answer, AnswerStream.preview(String.slice(json, 0, n)))
    end

    assert AnswerStream.preview(String.duplicate("x", 128_001)) == ""
    assert AnswerStream.preview(~S({"answer":12})) == ""
  end
end
