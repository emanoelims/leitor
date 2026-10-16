defmodule LeitorWeb.LibraryLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.Library
  alias Leitor.Pages

  setup %{conn: conn} do
    scope = user_scope_fixture()
    %{conn: log_in_user(conn, scope.user), scope: scope}
  end

  test "the shelf combines owned pages and imports with persistent filters and ordering", %{conn: conn, scope: scope} do
    {:ok, _} = Pages.create_page(scope, %{"title" => "Zebra thoughts", "body" => "A first thought."})
    {:ok, _} = Library.create_text(scope, %{title: "Alpha essay", body: "An imported passage.", source: "import"})
    {:ok, _} = Pages.create_page(user_scope_fixture(), %{"title" => "A private page", "body" => "Hidden."})
    {:ok, view, html} = live(conn, ~p"/pages")
    refute html =~ "A private page"
    assert has_element?(view, "#library-texts article", "Zebra thoughts")
    assert has_element?(view, "#library-texts article", "Alpha essay")
    assert has_element?(view, "#header-context-menu #page-create #open-page-import[role=menuitem]")
    assert has_element?(view, "#page-create-trigger[aria-haspopup=menu]")
    assert has_element?(view, "#header-context-menu #page-create-trigger.workspace-header-primary")
    refute has_element?(view, "#main-content #open-page-import")
    refute has_element?(view, "#main-content #new-free-page")
    view |> form("#library-sort", sort: "title") |> render_change()
    assert_patch(view)
    assert render(view) =~ ~r/Alpha essay.*Zebra thoughts/s
    view |> element("#pages-source-import") |> render_click()
    assert_patch(view)
    assert has_element?(view, "#library-texts article", "Alpha essay")
    refute has_element?(view, "#library-texts article", "Zebra thoughts")
    view |> form("#library-search", search: "missing") |> render_change()
    path = assert_patch(view)
    assert has_element?(view, "#library-empty", "No pages found.")
    {:ok, reopened, _} = live(conn, path)
    assert has_element?(reopened, "#library-query[value=missing]")
    assert has_element?(reopened, "#pages-source-import[aria-pressed=true]")
    assert has_element?(reopened, "#library-order option[value=title][selected]")
  end

  test "imports are contextual, validation keeps the dialog open, and uploaded files become pages", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/pages")
    refute has_element?(view, "#material-form")
    view |> element("#open-page-import") |> render_click()
    refute has_element?(view, "#material_title")
    view |> form("#material-form", material: %{body: ""}) |> render_submit()
    assert has_element?(view, "#page-import-dialog", "can't be blank")

    upload =
      file_input(view, "#material-form", :material, [
        %{name: "chapter.md", content: "# A new chapter\n\nA quiet imported chapter.", type: "text/markdown"}
      ])

    render_upload(upload, "chapter.md")
    view |> form("#material-form", material: %{body: ""}) |> render_submit()
    refute has_element?(view, "#page-import-dialog")
    assert has_element?(view, "#library-texts article", "A new chapter")
    assert [%{title: "A new chapter", body: "# A new chapter\n\nA quiet imported chapter."}] = Library.list_texts(scope)
  end

  test "an unreadable upload preserves typed text and closing the importer cancels its file", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/pages")
    render_click(view, "open-import")
    view |> form("#material-form", material: %{body: "# My chapter\n\nMy own text."}) |> render_change()
    upload = file_input(view, "#material-form", :material, [%{name: "bad.txt", content: <<255>>, type: "text/plain"}])
    render_upload(upload, "bad.txt")
    view |> form("#material-form", material: %{body: "# My chapter\n\nMy own text."}) |> render_submit()
    assert has_element?(view, "#page-import-dialog")
    assert render(view) =~ "not valid UTF-8"
    render_click(view, "close-import")
    render_click(view, "open-import")
    refute has_element?(view, "#material_title")
    assert has_element?(view, "#material_body", "# My chapter")
    refute has_element?(view, "#page-import-dialog p", "bad.txt")
  end

  test "pasted Markdown detects a title and ordinary prose falls back to Untitled", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/pages")

    for {body, title} <- [
          {"# A **quiet** discovery\n\nA passage.", "A quiet discovery"},
          {"An ordinary paragraph.", "Untitled"}
        ] do
      render_click(view, "open-import")
      view |> form("#material-form", material: %{body: body}) |> render_submit()
      refute has_element?(view, "#page-import-dialog")
      assert has_element?(view, "#library-texts h2", title)
      assert Enum.any?(Library.list_texts(scope), &(&1.title == title && &1.body == body))
    end
  end
end
