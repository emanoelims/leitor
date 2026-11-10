defmodule Leitor.Library.EpubTest do
  use ExUnit.Case, async: true

  alias Leitor.EpubFixtures
  alias Leitor.Library.Epub

  @moduletag :tmp_dir

  defp book!(tmp_dir, opts \\ []) do
    path = EpubFixtures.write!(Path.join(tmp_dir, "book.epub"), opts)
    assert {:ok, book} = Epub.extract_book(path)
    book
  end

  test "reads metadata and one chapter per spine document with navigation titles", %{tmp_dir: tmp_dir} do
    book = book!(tmp_dir)

    assert %{title: "A Small Book", author: "Ada Writer", language: "pt-BR", identifier: "urn:uuid:12345"} = book
    assert [%{title: "The Beginning", depth: 0}, %{title: "The Middle", depth: 0}] = book.chapters
    assert [first, second] = book.chapters
    assert first.id != second.id
    assert first.body =~ "<em>chapter</em>"
    refute first.body =~ "color: red"
  end

  test "reads titles from an EPUB 2 NCX", %{tmp_dir: tmp_dir} do
    chapters = [%{file: "a.xhtml", title: "From the NCX", body: "<p>No heading here.</p>"}]
    assert %{chapters: [%{title: "From the NCX"}]} = book!(tmp_dir, toc: :ncx, chapters: chapters)
  end

  test "falls back to the first heading and then to a numbered title", %{tmp_dir: tmp_dir} do
    chapters = [
      %{file: "a.xhtml", title: "ignored", body: "<h2>Found heading</h2><p>Text.</p>"},
      %{file: "b.xhtml", title: "ignored", body: "<p>Only a paragraph.</p>"}
    ]

    assert %{chapters: [%{title: "Found heading"}, %{title: "Chapter 2"}]} =
             book!(tmp_dir, toc: :none, chapters: chapters)
  end

  test "drops scripts, handlers, styles and unsafe links, and decodes entities", %{tmp_dir: tmp_dir} do
    body = ~S|<p onclick="x()">It&#8217;s <a href="javascript:alert(1)">bad</a><script>alert(1)</script></p>|
    chapters = [%{file: "a.xhtml", title: "Safe", body: body}]
    assert %{chapters: [%{body: html}]} = book!(tmp_dir, chapters: chapters)

    assert html =~ "It’s bad"
    refute html =~ ~r/script|onclick|javascript|alert/
  end

  test "rewrites links between chapters to the pages they become", %{tmp_dir: tmp_dir} do
    chapters = [
      %{file: "a.xhtml", title: "A", body: ~S|<p><a href="b.xhtml#note">see B</a></p>|},
      %{file: "b.xhtml", title: "B", body: ~S|<p id="note">Target</p>|}
    ]

    assert %{chapters: [first, second]} = book!(tmp_dir, chapters: chapters)
    assert first.body =~ ~s(href="/pages/#{second.id}#epub-note")
    assert second.body =~ ~s(id="epub-note")
  end

  test "does not link to a chapter without readable text", %{tmp_dir: tmp_dir} do
    chapters = [
      %{file: "a.xhtml", title: "A", body: ~S|<p><a href="b.xhtml">blank</a> Readable.</p>|},
      %{file: "b.xhtml", title: "B", body: "<p> </p>"}
    ]

    assert %{chapters: [%{body: html}]} = book!(tmp_dir, chapters: chapters)
    refute html =~ "/pages/"
  end

  test "splits a chapter that exceeds the text limit between top-level elements", %{tmp_dir: tmp_dir} do
    paragraph = "<p>" <> String.duplicate("word ", 1_000) <> "</p>"
    chapters = [%{file: "a.xhtml", title: "Long", body: String.duplicate(paragraph, 100)}]

    assert %{chapters: parts} = book!(tmp_dir, chapters: chapters)
    assert length(parts) > 1
    assert Enum.all?(parts, &(byte_size(&1.body) <= 250_000))
    assert [%{title: "Long (1/" <> _} | _] = parts
  end

  test "reports archives that are not EPUBs", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "broken.epub")
    File.write!(path, "not a zip")
    assert {:error, "We couldn't read this EPUB" <> _} = Epub.extract_book(path)
  end

  test "reports a book without readable text", %{tmp_dir: tmp_dir} do
    path =
      EpubFixtures.write!(Path.join(tmp_dir, "empty.epub"), chapters: [%{file: "a.xhtml", title: "A", body: "<p> </p>"}])

    assert {:error, "No readable text" <> _} = Epub.extract_book(path)
  end
end
