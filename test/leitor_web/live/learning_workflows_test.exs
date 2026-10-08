defmodule LeitorWeb.LearningWorkflowsTest do
  use LeitorWeb.ConnCase

  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.Accounts.Scope
  alias Leitor.Learning
  alias Leitor.Library

  setup %{conn: conn} do
    previous = Application.get_env(:leitor, :language_adapter)
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageStub)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:leitor, :language_adapter, previous),
        else: Application.delete_env(:leitor, :language_adapter)
    end)

    user = user_fixture()
    %{conn: log_in_user(conn, user), scope: Scope.for_user(user)}
  end

  test "public readers can paste and navigate, but cannot save without an account" do
    {:ok, view, _} = live(build_conn(), ~p"/")
    view |> element("button", "Paste text") |> render_click()
    view |> form("#reading-form", reading: %{title: "A story", body: "Hello world. Another sentence."}) |> render_submit()
    assert has_element?(view, "#current-sentence", "Hello")
    view |> element("#next-sentence") |> render_click()
    assert has_element?(view, "#current-sentence", "Another")
    view |> element("#save-reading") |> render_click()
    assert_redirect(view, ~p"/users/log-in")
  end

  test "saved readings resume, vocabulary is owned, and cards can be reviewed", %{conn: conn, scope: scope} do
    {:ok, text} =
      Library.create_text(scope, %{
        title: "My story",
        body: "Hello world. Another sentence.",
        source: "import",
        position: 0
      })

    {:ok, view, _} = live(conn, ~p"/read/#{text.id}")
    view |> element("#word-0") |> render_click()
    view |> element("button[phx-click='save-word'][phx-value-status='learning']") |> render_click()
    assert [%{term: "hello"}] = Learning.list_entries(scope)
    view |> element("button[aria-label='Close dialog']") |> render_click()
    view |> element("#next-sentence") |> render_click()
    assert Library.get_text!(scope, text.id).position == 1
    {:ok, vocabulary, _} = live(conn, ~p"/vocabulary")
    assert render(vocabulary) =~ "hello"
    {:ok, review, _} = live(conn, ~p"/review")
    render_click(review, "reveal")
    render_click(review, "rate", %{"rating" => "good"})
    assert Learning.next_review(scope) == nil
    assert Learning.progress(scope).attempts == 2
    {:ok, _, html} = live(conn, ~p"/progress")
    assert html =~ "Small steps add up"
  end

  test "writing feedback is saved, corrections become review cards, and drafts survive provider failures", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/write")
    view |> form("#writing-form", writing: %{text: "She go to school yesterday."}) |> render_submit()
    html = render_async(view)
    assert html =~ "Use the simple past"
    assert [%{kind: "writing"}] = Learning.recent_attempts(scope)
    view |> element("#review-correction-0") |> render_click()
    assert [%{term: "went", category: "error"}] = Learning.list_entries(scope)
    view |> element("#apply-correction") |> render_click()
    assert has_element?(view, "textarea", "She went to school yesterday.")
    render_submit(view, "save", %{"writing" => %{"text" => "My draft"}})
    assert length(Learning.recent_attempts(scope)) == 2
    view |> form("#writing-form", writing: %{text: "unavailable"}) |> render_submit()
    assert render_async(view) =~ "Your text is preserved"
    assert has_element?(view, "textarea", "unavailable")
  end

  test "dictation compares actual words, rewrite uses the tutor, shadowing saves only practice time", %{
    conn: conn,
    scope: scope
  } do
    {:ok, text} =
      Library.create_text(scope, %{
        title: "Practice",
        body: "She went to school yesterday.",
        position: 0,
        source: "import"
      })

    {:ok, view, _} = live(conn, ~p"/practice?#{%{text: text.id}}")
    view |> form("#practice-form", practice: %{answer: "she went to school yesterday"}) |> render_submit()
    assert has_element?(view, "#dictation-result", "100%")
    view |> element("a[aria-label=Rewrite]") |> render_click()
    view |> form("#practice-form", practice: %{answer: "She go to school yesterday."}) |> render_submit()
    assert render_async(view) =~ "Other ways to say it"
    view |> element("a[aria-label=Shadowing]") |> render_click()
    render_hook(view, "recorded", %{"duration" => 10})
    assert Enum.sort(Enum.map(Learning.recent_attempts(scope), & &1.kind)) == ["dictation", "rewrite", "shadowing"]
  end

  test "library imports pasted lesson materials and filters by title", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/lessons")
    view |> form("#material-form", material: %{title: "Unit 1", body: "A simple lesson."}) |> render_submit()
    assert [%{source: "lesson"}] = Library.list_texts(scope)
    assert has_element?(view, "#library-texts", "Unit 1")
    view |> form("#library-search", search: "missing") |> render_change()
    refute has_element?(view, "#library-texts article")
  end

  test "lesson guides persist and their words enter the owned review queue", %{conn: conn, scope: scope} do
    {:ok, lesson} =
      Library.create_text(scope, %{title: "Unit 2", body: "She went to school yesterday.", source: "lesson", position: 0})

    {:ok, view, _} = live(conn, ~p"/lessons/#{lesson.id}")
    view |> element("#analyze-lesson") |> render_click()
    assert render_async(view) =~ "Past tense"
    assert Library.get_text!(scope, lesson.id).analysis["grammar"]["title"] == "Past tense"
    view |> element("button[phx-click=save-word]") |> render_click()
    assert [%{term: "went", meaning: "foi"}] = Learning.list_entries(scope)
    {:ok, reopened, _} = live(conn, ~p"/lessons/#{lesson.id}")
    assert has_element?(reopened, "#lesson-vocabulary", "went")
    {:ok, _} = Library.delete_text(scope, Library.get_text!(scope, lesson.id))
    assert_patch(reopened, ~p"/lessons")
  end

  test "writing questions retain the editor and surface tutor failures", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/write")
    render_submit(view, "ask", %{"tutor" => %{"text" => "She go yesterday.", "question" => "Why past tense?"}})
    assert render_async(view) =~ "Yesterday calls for the simple past."
    assert has_element?(view, "#writing_text", "She go yesterday.")
    render_submit(view, "ask", %{"tutor" => %{"text" => "She go yesterday.", "question" => "unavailable"}})
    assert render_async(view) =~ "The tutor is unavailable"
    assert has_element?(view, "#writing_text", "She go yesterday.")
  end

  test "the private library validates imports, filters live updates, and deletes only owned texts", %{
    conn: conn,
    scope: scope
  } do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/library")
    {:ok, view, _} = live(conn, ~p"/library")
    view |> form("#material-form", material: %{title: "", body: ""}) |> render_submit()
    assert render(view) =~ "can&#39;t be blank"
    view |> form("#material-form", material: %{title: "A chapter", body: "Hello world."}) |> render_change()
    view |> form("#material-form", material: %{title: "A chapter", body: "Hello world."}) |> render_submit()
    assert [%{title: "A chapter"} = text] = Library.list_texts(scope)
    assert has_element?(view, "#library-texts article", "A chapter")
    view |> form("#library-search", search: "missing") |> render_change()
    refute has_element?(view, "#library-texts article")
    view |> form("#library-search", search: "chapter") |> render_change()
    assert has_element?(view, "#library-texts article", "A chapter")
    {:ok, _} = Library.update_text(scope, text, %{title: "Updated chapter"})
    assert render(view) =~ "Updated chapter"
    render_click(view, "delete", %{"id" => text.id})
    refute has_element?(view, "#library-texts article")
    assert Library.list_texts(scope) == []
  end

  test "public document upload prepares readable sentences and reports unreadable files" do
    {:ok, view, _} = live(build_conn(), ~p"/")

    upload =
      file_input(view, "#document-form", :document, [
        %{name: "chapter.txt", content: "A first sentence. A second sentence.", type: "text/plain"}
      ])

    assert render_upload(upload, "chapter.txt") =~ "chapter.txt"
    render_submit(view, "upload", %{})
    assert has_element?(view, "#current-sentence", "first")
    render_click(view, "move", %{"direction" => "previous"})
    assert has_element?(view, "#current-sentence", "first")
    {:ok, other, _} = live(build_conn(), ~p"/")
    upload = file_input(other, "#document-form", :document, [%{name: "bad.txt", content: <<255>>, type: "text/plain"}])
    render_upload(upload, "bad.txt")
    render_submit(other, "upload", %{})
    assert render(other) =~ "not valid UTF-8"
  end

  test "analysis preserves source text, expressions save together, and failed tutoring leaves the reading intact", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/")
    render_submit(view, "prepare", %{"reading" => %{"title" => "Practice", "body" => "She went to school yesterday."}})
    render_click(view, "analyze")
    assert render_async(view) =~ "Past tense"
    assert has_element?(view, "#current-sentence", "yesterday")
    render_click(view, "toggle", %{"layer" => "translation"})
    assert render(view) =~ "Ela foi"
    render_click(view, "toggle", %{"layer" => "structure"})
    render_click(view, "toggle", %{"layer" => "structure"})
    render_click(view, "phrase-mode")
    render_click(view, "select", %{"index" => "1"})
    render_click(view, "select", %{"index" => "3"})
    assert has_element?(view, "#word-dialog", "went to school")
    render_click(view, "save-word", %{"status" => "learning"})
    assert [%{term: "went to school", category: "expression"}] = Learning.list_entries(scope)
    render_click(view, "close")
    render_submit(view, "ask", %{"ask" => %{"question" => "Why past tense?"}})
    assert render_async(view) =~ "Yesterday calls for"
    render_submit(view, "prepare", %{"reading" => %{"title" => "Offline", "body" => "The tutor is unavailable."}})
    render_click(view, "analyze")
    assert render_async(view) =~ "Your reading is safe"
    assert has_element?(view, "#current-sentence", "unavailable")
    render_click(view, "save-text")
    assert_redirect(view)
    assert [%{body: "The tutor is unavailable."}] = Library.list_texts(scope)
  end

  test "word edits and status changes refresh filtered jars without losing other records", %{conn: conn, scope: scope} do
    {:ok, first} = Learning.save_word(scope, %{term: "has", meaning: "tem", category: "aux", context: "She has a book."})

    {:ok, _} =
      Learning.save_word(scope, %{term: "London", meaning: "Londres", category: "proper", context: "London is a city."})

    {:ok, view, _} = live(conn, ~p"/vocabulary")
    render_click(view, "filter", %{"category" => "verb"})
    assert render(view) =~ "has"
    refute has_element?(view, ".jar-words button", "London")
    render_click(view, "hide-empty")
    render_click(view, "open", %{"id" => first.id})
    render_submit(view, "edit", %{"entry" => %{"meaning" => "possesses", "category" => "verb"}})
    assert Learning.get_entry!(scope, first.id).meaning == "possesses"
    render_click(view, "known", %{"id" => first.id})
    render_click(view, "filter", %{"category" => "known"})
    assert has_element?(view, ".jar-words button", "has")
    render_click(view, "delete", %{"id" => first.id})
    refute has_element?(view, ".jar-words button")
    assert [%{term: "london"}] = Learning.list_entries(scope)
  end
end
