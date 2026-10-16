defmodule LeitorWeb.NotebookLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.Pages

  setup %{conn: conn} do
    scope = user_scope_fixture()
    %{scope: scope, conn: log_in_user(conn, scope.user)}
  end

  test "the global notebook requires login and starts with a useful empty state", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/notebook")
    {:ok, view, _} = live(conn, ~p"/notebook")
    assert has_element?(view, "#workspace-notebook[aria-current=page]")
    assert has_element?(view, "#notebook-result-count", "0 saved entries")
    assert has_element?(view, "#global-notebook-empty", "A place for your thoughts")
  end

  test "the notebook shows owned pages, follow-ups and safe Markdown with shareable filters", %{conn: conn, scope: scope} do
    {:ok, first} = Pages.create_page(scope, %{"title" => "First page", "body" => "An apple thought."})
    {:ok, second} = Pages.create_page(scope, %{"title" => "Second page", "body" => "An apple thought."})
    other = user_scope_fixture()
    {:ok, foreign} = Pages.create_page(other, %{"title" => "Someone else's page", "body" => "An apple thought."})
    anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 3, "end_offset" => 8}
    {:ok, note} = Pages.create_mark(scope, first.id, anchor, %{kind: "note", body: "**A good thought.**"})
    {:ok, _} = Pages.append_reply(scope, note.id, %{question: "More?", body: "A lasting thought."})
    {:ok, definition} = Pages.create_mark(scope, second.id, anchor, %{kind: "definition", body: "A fruit."})
    {:ok, _} = Pages.create_mark(other, foreign.id, anchor, %{kind: "note", body: "Hidden note."})
    {:ok, view, html} = live(conn, ~p"/notebook")
    assert has_element?(view, "#global-notebook-entries strong", "A good thought.")
    assert has_element?(view, "#global-notebook-entries", "A lasting thought.")
    assert has_element?(view, "#notebook-source-#{note.id}[href='/pages/#{first.id}?mark=#{note.id}']")
    refute html =~ foreign.title
    refute html =~ "Hidden note."
    view |> element("#global-notebook-filter-definition") |> render_click()
    assert has_element?(view, "#entries-#{definition.id}")
    refute has_element?(view, "#entries-#{note.id}")
    assert_patch(view)
    render_click(view, "clear")
    assert_patch(view)
    view |> form("#notebook-search", filters: %{search: "good", text_id: first.id}) |> render_change()
    path = assert_patch(view)
    assert path =~ "search=good"
    assert has_element?(view, "#entries-#{note.id}")
    refute has_element?(view, "#entries-#{definition.id}")
    {:ok, reopened, _} = live(conn, path)
    assert has_element?(reopened, "#notebook-result-count", "1 saved entry")
    {:ok, invalid, _} = live(conn, ~p"/notebook?#{[kind: "unknown", text_id: "invalid", page: "-1"]}")
    assert has_element?(invalid, "#notebook-result-count", "2 saved entries")
    {:ok, filtered, _} = live(conn, ~p"/notebook?#{[text_id: foreign.id]}")
    assert has_element?(filtered, "#notebook-result-count", "0 saved entries")
  end

  test "source links activate only an owned annotation on its own page and keep the page notebook", %{
    conn: conn,
    scope: scope
  } do
    {:ok, page} = Pages.create_page(scope, %{"title" => "Source", "body" => "An apple thought."})
    {:ok, other_page} = Pages.create_page(scope, %{"title" => "Other", "body" => "An apple thought."})
    anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 3, "end_offset" => 8}
    {:ok, note} = Pages.create_mark(scope, page.id, anchor, %{kind: "note", body: "Keep this."})
    {:ok, _} = Pages.update_page(scope, page, %{"body" => "A new opening.\n\nAn apple thought."})
    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}?#{[mark: note.id]}")
    assert has_element?(view, ".page-margin-card.is-active[data-margin-mark='#{note.id}']")
    note_id = note.id
    assert_push_event(view, "page-jump", %{id: ^note_id})
    view |> element("#page-notebook") |> render_click()
    assert has_element?(view, "#page-notebook-panel", "Keep this.")
    {:ok, unrelated, _} = live(conn, ~p"/pages/#{other_page.id}?#{[mark: note.id]}")
    refute has_element?(unrelated, ".page-margin-card.is-active")
    assert has_element?(unrelated, "#page-close[href='/pages']")
  end

  test "notes and owned word jars share one notebook with searchable, persistent word filters", %{
    conn: conn,
    scope: scope
  } do
    {:ok, word} =
      Leitor.Learning.save_word(scope, %{term: "has", meaning: "possesses", category: "aux", context: "She has a book."})

    {:ok, _} =
      Leitor.Learning.save_word(scope, %{
        term: "100%",
        meaning: "A literal percent",
        category: "word",
        context: "A precise amount."
      })

    {:ok, _} =
      Leitor.Learning.save_word(user_scope_fixture(), %{
        term: "private",
        meaning: "Hidden",
        category: "verb",
        context: "Hidden."
      })

    {:ok, view, _} = live(conn, ~p"/notebook")
    assert has_element?(view, "#notebook-notes-tab[aria-current=page]")
    refute has_element?(view, "#vocabulary-entries")
    view |> element("#notebook-words-tab") |> render_click()
    assert_patch(view, ~p"/notebook?view=words")
    assert has_element?(view, "#notebook-words-tab[aria-current=page]")
    assert has_element?(view, "#open-#{word.id}", "has")
    refute has_element?(view, "#vocabulary-entries", "private")
    view |> form("#word-search", words: %{search: "%"}) |> render_change()
    path = assert_patch(view)
    assert has_element?(view, "#vocabulary-entries", "100%")
    refute has_element?(view, "#open-#{word.id}")
    {:ok, reopened, _} = live(conn, path)
    assert has_element?(reopened, "#word-search input[value='%']")
    render_click(reopened, "word-category", %{"category" => "verb"})
    assert_patch(reopened)
    assert has_element?(reopened, "#words-empty")
    {:ok, verbs, _} = live(conn, ~p"/notebook?#{[view: "words", jar: "verb"]}")
    render_click(verbs, "open", %{"id" => word.id})
    verbs |> form("#entry-edit", entry: %{meaning: "", category: "verb"}) |> render_submit()
    assert has_element?(verbs, "#entry-edit", "can't be blank")
    assert Leitor.Learning.get_entry!(scope, word.id).meaning == "possesses"
    verbs |> form("#entry-edit", entry: %{meaning: "owns", category: "verb"}) |> render_submit()
    refute has_element?(verbs, "#vocabulary-dialog")
    assert has_element?(verbs, "#open-#{word.id}", "owns")

    {:ok, _} =
      Leitor.Learning.save_word(scope, %{
        term: "walk",
        meaning: "Move on foot",
        category: "verb",
        context: "A short walk."
      })

    assert render(verbs) =~ "walk"
    verbs |> element("#notebook-notes-tab") |> render_click()
    assert_patch(verbs, ~p"/notebook")
    assert has_element?(verbs, "#global-notebook-entries")
  end

  test "pagination retains source and kind filters and a new search returns to the first page", %{
    conn: conn,
    scope: scope
  } do
    {:ok, page} = Pages.create_page(scope, %{"title" => "Many thoughts", "body" => "An apple thought."})
    anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 3, "end_offset" => 8}

    for n <- 1..31 do
      assert {:ok, _} = Pages.create_mark(scope, page.id, anchor, %{kind: "note", body: "Thought #{n}"})
    end

    {:ok, view, _} = live(conn, ~p"/notebook?#{[kind: "note", text_id: page.id]}")
    assert has_element?(view, "#notebook-next")
    refute has_element?(view, "#notebook-previous")
    view |> element("#notebook-next") |> render_click()
    path = assert_patch(view)
    assert path =~ "page=2"
    assert path =~ "kind=note"
    assert path =~ page.id
    assert has_element?(view, ".notebook-pagination", "Page 2 of 2")
    assert has_element?(view, "#notebook-previous")
    refute has_element?(view, "#notebook-next")
    view |> form("#notebook-search", filters: %{search: "missing", text_id: page.id}) |> render_change()
    assert_patch(view)
    assert has_element?(view, "#notebook-result-count", "0 saved entries")
    refute has_element?(view, ".notebook-pagination")
  end
end
