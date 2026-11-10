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

  describe "images" do
    @png EpubFixtures.png()

    defp illustrated(tmp_dir, body, opts \\ []) do
      chapters = [%{file: "a.xhtml", title: "Pictures", body: body}]
      images = Keyword.get(opts, :images, [%{file: "img/a.png", data: @png}])
      book!(tmp_dir, Keyword.merge([chapters: chapters, images: images], Keyword.delete(opts, :images)))
    end

    test "keeps images a chapter shows as assets served by id", %{tmp_dir: tmp_dir} do
      book = illustrated(tmp_dir, ~S|<p>Text.</p><p><img src="img/a.png" alt="A diagram" onerror="x()"></p>|)

      assert [%{id: id, content_type: "image/png", data: @png, byte_size: size, digest: digest}] = book.assets
      assert size == byte_size(@png)
      assert digest == :crypto.hash(:sha256, @png)
      assert [%{body: html}] = book.chapters
      assert html =~ ~s(src="/book-assets/#{id}")
      assert html =~ ~s(alt="A diagram")
      refute html =~ "onerror"
      assert book.cover_asset_id == nil
    end

    test "resolves image paths relative to the chapter and ignores query strings", %{tmp_dir: tmp_dir} do
      book = illustrated(tmp_dir, ~S|<p><img src="./img/../img/a.png?v=2" alt=""></p><p>Caption.</p>|)
      assert [%{id: id}] = book.assets
      assert hd(book.chapters).body =~ "/book-assets/#{id}"
    end

    test "drops remote, embedded, unknown and SVG images", %{tmp_dir: tmp_dir} do
      body = """
      <p>Text.</p>
      <p><img src="https://tracker.test/pixel.png"><img src="//tracker.test/p.png">
      <img src="data:image/png;base64,AAAA"><img src="img/missing.png"><img src="img/vector.svg">
      <img src="javascript:alert(1)"><img alt="no source"></p>
      """

      images = [%{file: "img/vector.svg", data: "<svg onload='x()'/>"}, %{file: "img/a.png", data: @png}]
      book = illustrated(tmp_dir, body, images: images)

      assert book.assets == []
      refute hd(book.chapters).body =~ ~r/<img|tracker|data:|javascript|vector/
    end

    test "does not store images no chapter shows", %{tmp_dir: tmp_dir} do
      images = [%{file: "img/a.png", data: @png}, %{file: "img/unused.png", data: @png}]
      assert %{assets: [_]} = illustrated(tmp_dir, ~S|<p>One <img src="img/a.png"></p>|, images: images)
    end

    test "trusts the bytes, not the manifest or the extension", %{tmp_dir: tmp_dir} do
      images = [%{file: "img/fake.png", data: "<html><script>alert(1)</script></html>"}]
      book = illustrated(tmp_dir, ~S|<p>Text <img src="img/fake.png"></p>|, images: images)

      assert book.assets == []
      refute hd(book.chapters).body =~ "<img"
    end

    test "types JPEG, GIF and WebP by their signatures", %{tmp_dir: tmp_dir} do
      images = [
        %{file: "img/a.jpg", data: <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF">>},
        %{file: "img/b.gif", data: "GIF89a" <> <<1, 0, 1, 0, 0, 0, 0>>},
        %{file: "img/c.webp", data: "RIFF" <> <<4, 0, 0, 0>> <> "WEBPVP8 "}
      ]

      body = ~S|<p>Text <img src="img/a.jpg"><img src="img/b.gif"><img src="img/c.webp"></p>|
      assert %{assets: assets} = illustrated(tmp_dir, body, images: images)
      assert assets |> Enum.map(& &1.content_type) |> Enum.sort() == ["image/gif", "image/jpeg", "image/webp"]
    end

    test "skips an image over the size limit without failing the book", %{tmp_dir: tmp_dir} do
      big = <<0x89, "PNG\r\n", 0x1A, "\n">> <> :binary.copy(<<0>>, 8_000_001)
      images = [%{file: "img/big.png", data: big}, %{file: "img/a.png", data: @png}]
      body = ~S|<p>Text <img src="img/big.png"><img src="img/a.png"></p>|

      assert %{assets: [%{data: @png}], chapters: [%{body: html}]} = illustrated(tmp_dir, body, images: images)
      assert length(Regex.scan(~r/<img/, html)) == 1
    end

    test "counts the images it could not import", %{tmp_dir: tmp_dir} do
      body = ~S|<p>Text <img src="img/a.png"><img src="https://tracker.test/p.png"><img src="img/missing.png"></p>|
      assert %{skipped_images: 2} = illustrated(tmp_dir, body)
      assert %{skipped_images: 0} = illustrated(tmp_dir, ~S|<p>Text <img src="img/a.png"></p>|)
    end

    test "finds the cover from an EPUB 3 property or an EPUB 2 meta element", %{tmp_dir: tmp_dir} do
      cover = %{file: "img/cover.png", data: @png}
      body = "<p>No pictures here.</p>"

      for kind <- [:property, :meta] do
        book = illustrated(tmp_dir, body, images: [cover], cover: {kind, "img/cover.png"})
        assert [%{id: id}] = book.assets
        assert book.cover_asset_id == id
      end
    end

    test "ignores a cover that is not a usable image", %{tmp_dir: tmp_dir} do
      images = [%{file: "img/cover.png", data: "not an image"}]
      book = illustrated(tmp_dir, "<p>Text.</p>", images: images, cover: {:property, "img/cover.png"})
      assert book.assets == []
      assert book.cover_asset_id == nil
    end

    test "rejects an archive that declares more than 30 MB", %{tmp_dir: tmp_dir} do
      path =
        EpubFixtures.write!(Path.join(tmp_dir, "huge.epub"),
          images: [%{file: "img/x.png", data: :binary.copy(<<0>>, 31_000_000), type: "image/png"}]
        )

      assert {:error, "We couldn't read this EPUB" <> _} = Epub.extract_book(path)
    end
  end
end
