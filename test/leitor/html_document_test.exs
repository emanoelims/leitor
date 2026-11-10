defmodule Leitor.HtmlDocumentTest do
  use ExUnit.Case, async: true

  alias Leitor.HtmlDocument
  alias Leitor.Library.Epub.Sanitizer
  alias Leitor.PageDocument

  doctest HtmlDocument

  @chapter """
  <h1 id="epub-top">Chapter  One</h1>
  <p>Hello <em>wide</em> world &amp; “quotes”, café.<br>\nSecond line.</p>
  <ul><li>plain item</li><li><p>nested one</p><p>nested two</p></li></ul>
  <blockquote>loose <b>quote</b></blockquote>
  <table><tr><th>Head</th></tr><tr><td>cell</td><td></td></tr></table>
  <dl><dt>Term</dt><dd>Meaning</dd></dl>
  <pre>
   code line
     indented</pre>
  <hr>
  <p> </p>
  """

  # What a browser would report for a block: the text nodes of the rendered element.
  defp rendered_text(document, id) do
    document.html |> LazyHTML.from_fragment() |> LazyHTML.query(~s([data-page-block="#{id}"])) |> LazyHTML.text()
  end

  test "keeps server text byte-identical to the rendered block text" do
    document = HtmlDocument.prepare(@chapter)

    assert length(document.blocks) == 11
    assert Enum.map(document.blocks, & &1.id) == Enum.to_list(0..10)

    for block <- document.blocks do
      assert rendered_text(document, block.id) == block.text
      assert String.valid?(block.text)
      assert String.trim(block.text) != ""
    end

    assert document.text == Enum.map_join(document.blocks, "\n\n", & &1.text)
  end

  test "makes leaf elements blocks and containers wrappers without nesting blocks" do
    document = HtmlDocument.prepare(@chapter)
    texts = Enum.map(document.blocks, & &1.text)

    assert ["Chapter One", "Hello wide world & “quotes”, café.\nSecond line." | _] = texts
    assert "plain item" in texts and "nested one" in texts and "nested two" in texts
    assert "loose quote" in texts and "Head" in texts and "cell" in texts
    assert "Term" in texts and "Meaning" in texts
    assert " code line\n   indented" in texts

    fragment = LazyHTML.from_fragment(document.html)
    assert fragment |> LazyHTML.query("[data-page-block] [data-page-block]") |> Enum.count() == 0
    assert fragment |> LazyHTML.query("[data-page-block]") |> Enum.count() == 11
    assert fragment |> LazyHTML.query("td") |> Enum.count() == 2
  end

  test "numbers blocks like Markdown pages so margin numbers keep working" do
    document = HtmlDocument.prepare("<p>One</p><p>Two</p>")

    assert document.html =~ ~s(<span class="page-block-number" aria-hidden="true">1</span>)
    assert document.html =~ ~s(id="page-block-1" data-page-block="1")
  end

  test "renders nothing executable" do
    document =
      HtmlDocument.prepare(~S"""
      <p onclick="steal()">Safe <a href="javascript:alert(1)">link</a></p>
      <script>alert(1)</script><style>p{}</style><iframe src="//evil"></iframe>
      <img src="https://tracker/x.png"><form><input></form>
      """)

    refute document.html =~ ~r/script|onclick|javascript|iframe|<img|<form|<style|style=/i
    assert document.text == "Safe link"
  end

  test "is deterministic, and sanitising stored markup again changes nothing" do
    {:ok, tree} = Sanitizer.tree(@chapter, import?: true)
    stored = Sanitizer.to_html(tree)
    {:ok, again} = Sanitizer.tree(stored)

    assert Sanitizer.to_html(again) == stored
    assert HtmlDocument.prepare(stored) == HtmlDocument.prepare(stored)
    assert HtmlDocument.prepare(stored).text =~ "café.\nSecond line."
  end

  test "returns an empty document for oversized or empty markup" do
    assert %{html: "", blocks: [], text: ""} = HtmlDocument.prepare(String.duplicate("x", 4_000_001))
    assert %{blocks: [], text: ""} = HtmlDocument.prepare("<p> </p>")
  end

  describe "annotations" do
    test "select a quote across blocks with the shared selection contract" do
      document = HtmlDocument.prepare("<p>Alpha beta</p><p>Gamma delta</p>")

      anchor = %{"start_block" => 0, "end_block" => 1, "start_offset" => 6, "end_offset" => 5}
      assert {:ok, selection} = PageDocument.selection(document, anchor)
      assert selection.quote == "beta\n\nGamma"
      assert selection.block_index == 0
    end

    test "count UTF-8 bytes, so multibyte text anchors correctly" do
      document = HtmlDocument.prepare("<p>café au lait</p>")

      anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 0, "end_offset" => byte_size("café")}
      assert {:ok, %{quote: "café"}} = PageDocument.selection(document, anchor)

      inside_character = %{anchor | "end_offset" => byte_size("caf") + 1}
      assert {:error, :invalid_selection} = PageDocument.selection(document, inside_character)
    end

    test "are located again from their saved offsets" do
      document = HtmlDocument.prepare("<p>One</p><p>Two <em>three</em></p>")
      anchor = %{"start_block" => 1, "end_block" => 1, "start_offset" => 4, "end_offset" => 9}
      {:ok, selection} = PageDocument.selection(document, anchor)

      assert PageDocument.locate(document, selection) == selection
      assert selection.quote == "three"
    end
  end

  test "PageDocument dispatches by source" do
    assert PageDocument.for_text(%{source: "epub", body: "<p>Html</p>"}).text == "Html"
    assert PageDocument.for_text(%{source: "page", body: "# Markdown"}).text == "Markdown"
    assert PageDocument.for_text(%{source: "import", body: "*plain*"}).text == "plain"
  end
end
