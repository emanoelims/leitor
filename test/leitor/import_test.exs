defmodule Leitor.Library.ImportTest do
  use ExUnit.Case, async: true

  alias Leitor.Library.Import

  doctest Import

  setup do
    path = Path.join(System.tmp_dir!(), "leitor-title-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "detects ATX and setext titles, flattens formatting, and ignores code or quoted headings" do
    assert Import.title("\uFEFF# A **quiet** [discovery](https://example.test)\n\nA passage.") == "A quiet discovery"
    assert Import.title("A discovery\n===========\n\nA passage.") == "A discovery"
    assert Import.title("An opening paragraph.\n\n## Another discovery\n\nMore prose.") == "Another discovery"
    assert Import.title("```md\n# A fake title\n```\n\nAn ordinary paragraph.") == "Untitled"
    assert Import.title("> # A quotation\n\nAn ordinary paragraph.") == "Untitled"
    assert Import.title("# " <> String.duplicate("é", 220)) == String.duplicate("é", 180)
    assert Import.title("Short plain title\r\n\r\nA passage.") == "Short plain title"
    assert Import.title("An ordinary paragraph.\n\nAnother paragraph.") == "Untitled"
    assert Import.title("") == "Untitled"
  end

  test "Markdown extensions preserve content and filenames do not become titles", %{path: path} do
    body = "# A **real** title\n\nA passage."
    File.write!(path, body)

    for name <- ["unrelated.MD", "unrelated.markdown", "unrelated.txt"] do
      assert {:ok, %{title: "A real title", body: ^body}} = Import.extract_document(path, name)
    end

    File.write!(path, "An ordinary paragraph.")
    assert {:ok, %{title: "Untitled"}} = Import.extract_document(path, "an-invented-title.txt")
    File.write!(path, <<255>>)
    assert {:error, "This document is not valid UTF-8 text."} = Import.extract_document(path, "invalid.md")
  end

  test "DOCX metadata supplies the title while missing metadata falls back to the opening title", %{path: path} do
    body = "<w:document><w:p><w:t>Opening title</w:t></w:p><w:p><w:t>A passage.</w:t></w:p></w:document>"

    zip!(path, [
      {~c"word/document.xml", body},
      {~c"docProps/core.xml", "<cp:coreProperties><dc:title>Thoughts &amp; words</dc:title></cp:coreProperties>"}
    ])

    assert {:ok, %{title: "Thoughts & words", body: text}} = Import.extract_document(path, "book.docx")
    assert text =~ "A passage."
    zip!(path, [{~c"word/document.xml", body}])
    assert {:ok, %{title: "Opening title"}} = Import.extract_document(path, "book.docx")
    zip!(path, [{~c"word/document.xml", body}, {~c"docProps/core.xml", <<255>>}])
    assert {:ok, %{title: "Opening title"}} = Import.extract_document(path, "book.docx")
  end

  test "EPUB title metadata is separate from spine-ordered reading content", %{path: path} do
    container = ~s(<container><rootfiles><rootfile full-path="book/package.opf"/></rootfiles></container>)

    package =
      ~s(<package><metadata><dc:title>A collected work</dc:title></metadata><manifest><item id="chapter" href="chapter.xhtml"/></manifest><spine><itemref idref="chapter"/></spine></package>)

    zip!(path, [
      {~c"META-INF/container.xml", container},
      {~c"book/package.opf", package},
      {~c"book/chapter.xhtml", "<h1>A chapter title</h1><p>A passage.</p>"}
    ])

    assert {:ok, %{title: "A collected work", body: body}} = Import.extract_document(path, "book.epub")
    assert body =~ "A chapter title"
    refute body =~ "A collected work"
  end

  @tag skip: is_nil(System.find_executable("pdfinfo")) or is_nil(System.find_executable("pdftotext"))
  test "PDF title metadata is detected when local PDF tools are available", %{path: path} do
    File.write!(path, pdf("A PDF title"))
    assert {:ok, %{title: "A PDF title", body: body}} = Import.extract_document(path, "book.pdf")
    assert body =~ "An ordinary paragraph."
    File.write!(path, pdf(""))
    assert {:ok, %{title: "Untitled"}} = Import.extract_document(path, "book.pdf")
  end

  defp zip!(path, entries) do
    {:ok, {_, data}} = :zip.create(~c"document.zip", entries, [:memory])
    File.write!(path, data)
  end

  defp pdf(title) do
    stream = "BT /F1 12 Tf 72 720 Td (An ordinary paragraph.) Tj ET"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< /Length #{byte_size(stream)} >>\nstream\n#{stream}\nendstream",
      "<< /Title (#{title}) >>"
    ]

    header = "%PDF-1.4\n"

    {parts, {offsets, size}} =
      Enum.map_reduce(Enum.with_index(objects, 1), {[], byte_size(header)}, fn {object, id}, {offsets, size} ->
        part = "#{id} 0 obj\n#{object}\nendobj\n"
        {part, {offsets ++ [size], size + byte_size(part)}}
      end)

    xref =
      Enum.map_join(offsets, "", fn offset -> String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n" end)

    header <>
      Enum.join(parts) <>
      "xref\n0 7\n0000000000 65535 f \n" <>
      xref <> "trailer\n<< /Size 7 /Root 1 0 R /Info 6 0 R >>\nstartxref\n#{size}\n%%EOF"
  end
end
