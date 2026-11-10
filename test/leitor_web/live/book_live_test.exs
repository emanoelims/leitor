defmodule LeitorWeb.BookLiveTest do
  use LeitorWeb.ConnCase

  import ExUnit.CaptureLog
  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.EpubFixtures
  alias Leitor.Library
  alias Leitor.Pages
  alias Leitor.Sharing

  @chapters [
    %{file: "one.xhtml", title: "The Beginning", body: "<h1>The Beginning</h1><p>A wonderful first chapter.</p>"},
    %{file: "two.xhtml", title: "The Middle", body: "<h1>The Middle</h1><p>The second chapter &amp; more.</p>"}
  ]

  setup %{conn: conn} do
    scope = user_scope_fixture()
    %{conn: log_in_user(conn, scope.user), scope: scope}
  end

  defp import_book(conn, opts \\ []) do
    {:ok, view, _} = live(conn, ~p"/pages")
    view |> element("#open-page-import") |> render_click()
    content = EpubFixtures.binary!(Keyword.put_new(opts, :chapters, @chapters))

    upload =
      file_input(view, "#material-form", :material, [%{name: "book.epub", content: content, type: "application/epub+zip"}])

    render_upload(upload, "book.epub")
    view |> form("#material-form", material: %{body: ""}) |> render_submit()
    view
  end

  defp create_book(scope) do
    {:ok, extracted} =
      scope
      |> then(fn _ ->
        EpubFixtures.write!(Path.join(System.tmp_dir!(), "book-#{System.unique_integer([:positive])}.epub"),
          chapters: @chapters
        )
      end)
      |> Library.Epub.extract_book()

    {:ok, book} = Library.create_book(scope, extracted)
    {book, Library.book_chapters(scope, book)}
  end

  describe "importing" do
    test "an EPUB becomes one book and opens at its first chapter", %{conn: conn, scope: scope} do
      view = import_book(conn)

      assert [%{title: "A Small Book", author: "Ada Writer", chapter_count: 2} = book] = Library.list_books(scope)
      assert [first, _second] = Library.book_chapters(scope, book)
      assert_redirect(view, ~p"/pages/#{first.id}")
      assert Library.list_texts(scope) == []
    end

    test "an unreadable EPUB keeps the importer open with a message", %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/pages")
      view |> element("#open-page-import") |> render_click()

      upload =
        file_input(view, "#material-form", :material, [%{name: "bad.epub", content: "nope", type: "application/epub+zip"}])

      render_upload(upload, "bad.epub")
      view |> form("#material-form", material: %{body: ""}) |> render_submit()

      assert has_element?(view, "#page-import-dialog")
      assert render(view) =~ "couldn&#39;t read this EPUB" or render(view) =~ "couldn't read this EPUB"
      assert Library.list_books(scope) == []
    end
  end

  describe "the shelf" do
    test "shows a book as one card, not as its chapters, and filters it as imported", %{conn: conn, scope: scope} do
      {book, [first | _]} = create_book(scope)
      {:ok, _} = Pages.create_page(scope, %{"title" => "My own page", "body" => "Written here."})
      {:ok, view, _} = live(conn, ~p"/pages")

      assert has_element?(view, "#library-texts article", "A Small Book")
      assert has_element?(view, ~s(#book-#{book.id}-open[href="/pages/#{first.id}"]))
      refute has_element?(view, "#library-texts article", "The Middle")

      view |> element("#pages-source-page") |> render_click()
      refute has_element?(view, "#library-texts article", "A Small Book")
      assert has_element?(view, "#library-texts article", "My own page")

      view |> element("#pages-source-import") |> render_click()
      assert has_element?(view, "#library-texts article", "A Small Book")
    end

    test "finds a book by author and deletes it with its chapters", %{conn: conn, scope: scope} do
      {book, [first | _]} = create_book(scope)
      {:ok, view, _} = live(conn, ~p"/pages")

      view |> form("#library-search", %{search: "ada writer"}) |> render_change()
      assert has_element?(view, "#library-texts article", "A Small Book")

      render_click(view, "delete-book", %{"id" => book.id})
      refute has_element?(view, "#library-texts article", "A Small Book")
      assert Library.list_books(scope) == []
      assert_raise Ecto.NoResultsError, fn -> Library.get_text!(scope, first.id) end
    end

    test "never deletes another reader's book", %{conn: conn} do
      owner = user_scope_fixture()
      {book, _} = create_book(owner)
      {:ok, view, _} = live(conn, ~p"/pages")
      Process.flag(:trap_exit, true)

      # The LiveView process exits on the missing record, exactly as it does for another reader's text.
      capture_log(fn ->
        assert {{%Ecto.NoResultsError{}, _}, _} = catch_exit(render_click(view, "delete-book", %{"id" => book.id}))
      end)

      assert Library.get_book!(owner, book.id)
    end
  end

  describe "the book page" do
    test "lists chapters in order and continues where reading stopped", %{conn: conn, scope: scope} do
      {book, [first, second]} = create_book(scope)
      {:ok, view, _} = live(conn, ~p"/books/#{book.id}")

      assert has_element?(view, "#book-title", "A Small Book")
      assert has_element?(view, "#book-toc li", "The Beginning")
      assert has_element?(view, ~s(#book-continue[href="/pages/#{first.id}"]), "Start reading")

      {:ok, _chapter, _} = live(conn, ~p"/pages/#{second.id}")
      {:ok, view, _} = live(conn, ~p"/books/#{book.id}")
      assert has_element?(view, ~s(#book-continue[href="/pages/#{second.id}"]), "Continue reading")
      assert has_element?(view, "#chapter-#{second.id}.is-current")
    end

    test "deletes the book", %{conn: conn, scope: scope} do
      {book, _} = create_book(scope)
      {:ok, view, _} = live(conn, ~p"/books/#{book.id}")

      view |> element("#book-delete") |> render_click()
      assert_redirect(view, ~p"/pages")
      assert Library.list_books(scope) == []
    end

    test "belongs to its owner", %{conn: conn} do
      {book, _} = create_book(user_scope_fixture())
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/books/#{book.id}") end
    end
  end

  describe "reading a chapter" do
    test "renders the chapter with navigation and without editing", %{conn: conn, scope: scope} do
      {book, [first, second]} = create_book(scope)
      {:ok, view, _} = live(conn, ~p"/pages/#{first.id}")

      assert has_element?(view, "#chapter-nav", "A Small Book")
      assert has_element?(view, ~s(#chapter-toc[href="/books/#{book.id}"]))
      assert has_element?(view, "#page-reading h1", "The Beginning")
      assert has_element?(view, ~s(#page-reading[lang="pt-BR"]))
      assert has_element?(view, "#page-reading [data-page-block]", "A wonderful first chapter.")
      refute has_element?(view, "#chapter-prev")
      assert has_element?(view, ~s(#chapter-next[href="/pages/#{second.id}"]))
      assert has_element?(view, "#chapter-next-end", "The Middle")
      refute has_element?(view, "#page-edit")

      render_click(view, "edit")
      refute has_element?(view, "#page-save")
      assert render_hook(view, "save", %{"page" => %{"title" => "x", "body" => "y"}}) =~ "can&#39;t be edited"
      assert Library.get_text!(scope, first.id).source == "epub"

      {:ok, next, _} = live(conn, ~p"/pages/#{second.id}")
      assert has_element?(next, ~s(#chapter-prev[href="/pages/#{first.id}"]))
      refute has_element?(next, "#chapter-next")
      refute has_element?(next, "#chapter-next-end")
      assert has_element?(next, ".page-end")
    end

    test "highlights and notes anchor to the chapter text", %{conn: conn, scope: scope} do
      {_book, [first | _]} = create_book(scope)
      {:ok, view, _} = live(conn, ~p"/pages/#{first.id}")

      # Block 0 is the heading, block 1 the paragraph "A wonderful first chapter."
      anchor = %{"start_block" => 1, "end_block" => 1, "start_offset" => 2, "end_offset" => 11}
      render_hook(view, "select", anchor)
      assert has_element?(view, "#page-selection")
      view |> element("#selection-highlight") |> render_click()

      assert [%{kind: "highlight", quote: "wonderful", block_index: 1}] = Pages.list_marks(scope, first.id)

      render_hook(view, "select", anchor)
      render_click(view, "selection-mode", %{"mode" => "note"})
      render_submit(view, "note", %{"note" => %{"body" => "Worth remembering."}})
      assert Enum.any?(Pages.list_marks(scope, first.id), &(&1.kind == "note" and &1.body == "Worth remembering."))
    end

    test "rejects a selection outside the chapter's blocks", %{conn: conn, scope: scope} do
      {_book, [first | _]} = create_book(scope)
      {:ok, view, _} = live(conn, ~p"/pages/#{first.id}")

      render_hook(view, "select", %{"start_block" => 9, "end_block" => 9, "start_offset" => 0, "end_offset" => 3})
      refute has_element?(view, "#page-selection")
    end

    test "is private to its owner", %{conn: conn} do
      {_book, [first | _]} = create_book(user_scope_fixture())
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/pages/#{first.id}") end
    end
  end

  describe "sharing a chapter" do
    test "visitors read the rendered chapter and comment on it", %{scope: scope} do
      {_book, [first | _]} = create_book(scope)
      {:ok, share} = Sharing.set_link(scope, first.id, %{"link_role" => "comment"})

      {:ok, visitor, html} = live(build_conn(), ~p"/s/#{share.token}")
      assert html =~ "A wonderful first chapter."

      render_hook(visitor, "select", %{"start_block" => 1, "end_block" => 1, "start_offset" => 2, "end_offset" => 11})
      visitor |> element("#selection-comment") |> render_click()

      visitor
      |> form("#shared-comment-form", comment: %{author_name: "Visitor", body: "A shared question"})
      |> render_submit()

      assert has_element?(visitor, "#shared-comments", "A shared question")
      assert {:ok, %{entries: [%{quote: "wonderful"}]}} = Sharing.comments(nil, share.token)
    end
  end

  describe "images" do
    @png EpubFixtures.png()

    @illustrated [
      %{
        file: "one.xhtml",
        title: "Plates",
        body: ~S|<h1>Plates</h1><p>Look at this.</p><p><img src="img/plate.png" alt="A plate"></p><p>After the plate.</p>|
      }
    ]

    defp illustrated_book(scope) do
      path =
        EpubFixtures.write!(Path.join(System.tmp_dir!(), "plates-#{System.unique_integer([:positive])}.epub"),
          chapters: @illustrated,
          images: [%{file: "img/plate.png", data: @png}, %{file: "img/cover.png", data: @png}],
          cover: {:property, "img/cover.png"}
        )

      {:ok, extracted} = Library.Epub.extract_book(path)
      {:ok, book} = Library.create_book(scope, extracted)
      {Library.get_book!(scope, book.id), hd(Library.book_chapters(scope, book))}
    end

    test "the shelf card and the book page show the cover", %{conn: conn, scope: scope} do
      {book, _chapter} = illustrated_book(scope)
      cover = ~s([src="/book-assets/#{book.cover_asset_id}"])

      {:ok, shelf, _} = live(conn, ~p"/pages")
      assert has_element?(shelf, "#library-texts img.book-card-cover#{cover}")

      {:ok, page, _} = live(conn, ~p"/books/#{book.id}")
      assert has_element?(page, "#book-cover#{cover}")
    end

    test "a chapter shows its image and keeps text anchors", %{conn: conn, scope: scope} do
      {_book, chapter} = illustrated_book(scope)
      {:ok, view, _} = live(conn, ~p"/pages/#{chapter.id}")

      assert has_element?(view, ~s(#page-reading img[alt="A plate"][src^="/book-assets/"]))
      assert has_element?(view, "#page-reading [data-page-block]", "After the plate.")

      # Blocks: 0 heading, 1 "Look at this.", 2 "After the plate." (the image has no block).
      render_hook(view, "select", %{"start_block" => 2, "end_block" => 2, "start_offset" => 0, "end_offset" => 5})
      view |> element("#selection-highlight") |> render_click()
      assert [%{quote: "After", block_index: 2}] = Pages.list_marks(scope, chapter.id)
    end

    test "a shared chapter serves its images through the link", %{scope: scope} do
      {_book, chapter} = illustrated_book(scope)
      {:ok, share} = Sharing.set_link(scope, chapter.id, %{"link_role" => "view"})

      {:ok, visitor, _} = live(build_conn(), ~p"/s/#{share.token}")
      assert has_element?(visitor, ~s(#page-reading img[src^="/s/#{share.token}/book-assets/"]))
      refute has_element?(visitor, ~s(#page-reading img[src^="/book-assets/"]))
    end

    test "importing an EPUB stores its images and cover", %{conn: conn, scope: scope} do
      import_book(conn,
        chapters: @illustrated,
        images: [%{file: "img/plate.png", data: @png}, %{file: "img/cover.png", data: @png}],
        cover: {:meta, "img/cover.png"}
      )

      assert [%{cover_asset_id: cover}] = Library.list_books(scope)
      assert {:ok, %{data: @png}} = Library.get_book_asset(scope, cover)
    end

    test "tells the reader how many images could not be imported", %{conn: conn} do
      chapters = [
        %{file: "one.xhtml", title: "One", body: ~S|<p>Text <img src="img/a.png"><img src="https://x.test/y.png"></p>|}
      ]

      view = import_book(conn, chapters: chapters, images: [%{file: "img/a.png", data: @png}])
      {_path, flash} = assert_redirect(view)
      assert flash["info"] =~ "1 image couldn't be imported"
    end

    test "says nothing about images when all were imported", %{conn: conn} do
      view = import_book(conn)
      {_path, flash} = assert_redirect(view)
      refute flash["info"] =~ "image"
    end

    test "accepts an EPUB over 10 MB", %{conn: conn, scope: scope} do
      png = fn -> <<0x89, "PNG\r\n", 0x1A, "\n">> <> :crypto.strong_rand_bytes(7_000_000) end
      chapters = [%{file: "one.xhtml", title: "Big", body: ~S|<p>Text <img src="img/a.png"><img src="img/b.png"></p>|}]

      import_book(conn,
        chapters: chapters,
        images: [%{file: "img/a.png", data: png.()}, %{file: "img/b.png", data: png.()}]
      )

      assert [%{chapter_count: 1}] = Library.list_books(scope)
    end

    test "still refuses other documents over 10 MB", %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/pages")
      view |> element("#open-page-import") |> render_click()
      content = "# Heavy\n\n" <> String.duplicate("a", 10_000_001)

      upload =
        file_input(view, "#material-form", :material, [%{name: "heavy.md", content: content, type: "text/markdown"}])

      render_upload(upload, "heavy.md")
      view |> form("#material-form", material: %{body: ""}) |> render_submit()

      assert has_element?(view, "#page-import-dialog")
      assert Library.list_texts(scope) == []
    end
  end
end
