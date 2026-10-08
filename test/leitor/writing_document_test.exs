defmodule Leitor.WritingDocumentTest do
  use ExUnit.Case, async: true

  alias Leitor.WritingDocument

  test "legacy drafts keep literal Markdown and newline paragraphs" do
    assert WritingDocument.format(%{}) == "plain"
    assert WritingDocument.format(%{"format" => "html"}) == "plain"
    assert WritingDocument.format(%{"format" => "markdown"}) == "markdown"
    assert Enum.map(WritingDocument.paragraphs("# Literal\n\nCafé\n ", "plain"), & &1.text) == ["# Literal", "Café"]
  end

  test "Markdown selects prose blocks, preserving byte offsets and excluding code" do
    source =
      "# Café\n\n- **First** item\n- [x] Second\n\n> Quoted\n> words\n\n```elixir\nraise :example\n```\n\n---\n\nLast line\nsoft break"

    parts = WritingDocument.paragraphs(source, "markdown")

    assert Enum.map(parts, & &1.text) == [
             "# Café",
             "**First** item",
             "Second",
             "Quoted\n> words",
             "Last line\nsoft break"
           ]

    for part <- parts, do: assert(binary_part(source, part.start, part.length) == part.text)
    assert WritingDocument.paragraph(source, "markdown", -1) == nil
    assert WritingDocument.paragraph(source, "markdown", 20) == nil
    assert WritingDocument.paragraph(source, "markdown", 2).text == "Second"
    assert WritingDocument.paragraphs("", "markdown") == []
  end

  test "safe rendering supports formatting without executing HTML or HEEx" do
    html =
      WritingDocument.render(
        ~s|# Heading\n\n**Bold** and *italic* with ~~strike~~.\n\n- [x] Done\n\n<script>alert(1)</script>\n\n[bad](javascript:alert(1))\n\n![remote](https://example.com/tracker.png)\n\n<.link href="/">No component</.link>\n\n{System.cmd("echo", ["unsafe"])}|
      )

    assert html =~ "<h1>Heading</h1>"
    assert html =~ "<strong>Bold</strong>"
    assert html =~ "<em>italic</em>"
    assert html =~ "<del>strike</del>"
    assert html =~ "Done"
    assert html =~ "contains-task-list"
    assert html =~ "task-list-item"
    assert html =~ "type=\"checkbox\""
    assert html =~ "disabled"
    assert html =~ "aria-label=\"Task completed\""
    assert html =~ "checked"
    assert html =~ "No component"
    assert html =~ "System.cmd"
    refute html =~ "<script"
    refute html =~ "javascript:"
    refute html =~ "<img"
    refute html =~ "<.link"
  end

  test "word counts ignore block markers and code, and empty headings are not reviewable" do
    assert WritingDocument.word_count("# Café\n\n**One** word\n\n- [x] Done\n\n```\nnot prose\n```", "markdown") == 4
    assert WritingDocument.word_count("One two", "plain") == 2
    assert WritingDocument.word_count("", "markdown") == 0
    assert WritingDocument.word_count("> First\n>\n> Second", "markdown") == 2
    assert WritingDocument.word_count("<script>bad()</script>\n\n<span>Text</span>", "markdown") == 1
    assert "# \n\nReal text" |> WritingDocument.paragraphs("markdown") |> Enum.map(& &1.text) == ["Real text"]
  end

  test "explicit empty paragraphs render without entering the tutor's paragraph count" do
    source = "First.\n\n&nbsp;\n\nThird."
    assert source |> WritingDocument.paragraphs("markdown") |> Enum.map(& &1.text) == ["First.", "Third."]
    assert WritingDocument.word_count(source, "markdown") == 2
    assert length(Regex.scan(~r/<p>/, WritingDocument.render(source))) == 3
  end
end
