defmodule LeitorWeb.PageLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.Learning
  alias Leitor.Pages

  setup %{conn: conn} do
    scope = user_scope_fixture()
    previous = Application.get_env(:leitor, :language_adapter)
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageStub)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:leitor, :language_adapter, previous),
        else: Application.delete_env(:leitor, :language_adapter)
    end)

    %{conn: log_in_user(conn, scope.user), scope: scope}
  end

  test "already-open editors and readers use the account's latest AI preferences", %{conn: conn, scope: scope} do
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageGate)
    Application.put_env(:leitor, :language_test_owner, self())
    on_exit(fn -> Application.delete_env(:leitor, :language_test_owner) end)
    {:ok, page} = Pages.create_page(scope, %{"title" => "Thoughts", "body" => "A wonderful sentence."})
    {:ok, reader, _} = live(conn, ~p"/pages/#{page.id}")
    {:ok, editor, _} = live(conn, ~p"/pages/new")

    {:ok, _} =
      Leitor.Accounts.update_preferences(scope, %{
        ai_locale: "pt_BR",
        reading_model: "anthropic:claude-opus-5-5",
        writing_model: "anthropic:claude-sonnet-5-5"
      })

    render_hook(reader, "select", %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11})
    render_click(reader, "help", %{"action" => "define"})
    assert_receive {:language_settings, "anthropic:claude-opus-5-5", prompt}
    assert prompt =~ "Preferred response language: Brazilian Portuguese"
    assert_receive {:language_started, reading_task}
    send(reading_task, {:complete, {:ok, %{"answer" => "Maravilhoso.", "meaning" => "maravilhoso", "category" => "adj"}}})
    render_async(reader)
    assert has_element?(reader, ".page-answer", "Maravilhoso.")

    render_hook(editor, "generate-page-text", %{
      "request_id" => "preferences",
      "prompt" => "A thought",
      "title" => "",
      "context" => ""
    })

    assert_receive {:language_settings, "anthropic:claude-sonnet-5-5", prompt}
    assert prompt =~ "Preferred response language: Brazilian Portuguese"
    assert_receive {:language_started, writing_task}
    send(writing_task, {:complete, {:ok, %{"markdown" => "Uma ideia."}}})
    render_async(editor)
    assert_push_event(editor, "page-ai-result", %{request_id: "preferences", markdown: "Uma ideia."})
  end

  test "every product entry requires login" do
    for path <- [~p"/", ~p"/pages", ~p"/pages/new", ~p"/notebook"] do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), path)
    end
  end

  test "editor generation returns Markdown, supports cancellation and ignores late results", %{conn: conn, scope: scope} do
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageGate)
    Application.put_env(:leitor, :language_test_owner, self())
    on_exit(fn -> Application.delete_env(:leitor, :language_test_owner) end)
    {:ok, view, _} = live(conn, ~p"/pages/new")
    assert has_element?(view, "#writing-block-ai", "Generate with AI")
    assert has_element?(view, "#page-ai-prompt[maxlength='2000']")
    request = %{"request_id" => "first", "prompt" => "Write a story", "context" => "A draft", "title" => "A title"}
    render_hook(view, "generate-page-text", request)
    assert_receive {:language_started, task}
    send(task, {:delta, "## A story\n\n<script>alert('unsafe')</script>"})
    assert_push_event(view, "page-ai-chunk", %{request_id: "first", html: html}, 500)
    assert html =~ "<h2>A story</h2>"
    refute html =~ "<script>"
    render_hook(view, "generate-page-text", %{request | "request_id" => "duplicate"})
    refute_receive {:language_started, _}
    send(task, {:complete, {:ok, %{"markdown" => "## A story\n\nA new beginning."}}})
    render_async(view)
    assert_push_event(view, "page-ai-result", %{request_id: "first", markdown: "## A story\n\nA new beginning."})
    assert Leitor.Library.list_texts(scope) == []

    render_hook(view, "generate-page-text", %{request | "request_id" => "cancelled"})
    assert_receive {:language_started, cancelled}
    ref = Process.monitor(cancelled)
    assert has_element?(view, "#page-save[disabled]")
    view |> element("#page-ai-stop") |> render_click()
    assert_push_event(view, "page-ai-stopped", %{request_id: "cancelled"})
    assert_receive {:DOWN, ^ref, :process, ^cancelled, _}
    send(view.pid, {:page_generation_delta, "cancelled", "Late text"})
    send(view.pid, {:flush_page_generation, "cancelled"})
    render(view)
    refute_push_event(view, "page-ai-chunk", %{request_id: "cancelled"})
    refute_push_event(view, "page-ai-result", %{request_id: "cancelled"})

    render_hook(view, "generate-page-text", %{request | "request_id" => "failure"})
    assert_receive {:language_started, failed}
    send(failed, {:complete, {:error, :unavailable}})
    render_async(view)
    assert_push_event(view, "page-ai-result", %{request_id: "failure", error: error})
    assert error =~ "Claude API key"

    render_hook(view, "generate-page-text", %{request | "request_id" => "crash"})
    assert_receive {:language_started, crashed}
    send(crashed, {:complete, {:error, :provider_error}})
    render_async(view)
    assert_push_event(view, "page-ai-result", %{request_id: "crash", error: error})
    assert error =~ "draft is safe"

    render_hook(view, "generate-page-text", %{request | "request_id" => "save-during-generation"})
    assert_receive {:language_started, interrupted}
    interrupted_ref = Process.monitor(interrupted)
    render_submit(view, "save", %{"page" => %{"title" => "Saved", "body" => "Keep my draft."}})
    assert_receive {:DOWN, ^interrupted_ref, :process, ^interrupted, _}
    render_hook(view, "generate-page-text", %{request | "request_id" => "reader"})
    refute_receive {:language_started, _}
    assert has_element?(view, "#page-reading", "Keep my draft.")
    render_click(view, "edit")
    render_hook(view, "generate-page-text", %{request | "request_id" => "edit-again", "prompt" => " "})
    render_async(view)
    assert_push_event(view, "page-ai-result", %{request_id: "edit-again", error: error})
    assert error =~ "1–2,000"
  end

  test "primary screens share navigation while account controls stay outside the menu slot", %{conn: conn} do
    for {path, active} <- [
          {~p"/pages", "workspace-pages"},
          {~p"/notebook?view=words", "workspace-notebook"},
          {~p"/notebook", "workspace-notebook"}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#app-header #workspace-context-trigger")
      assert has_element?(view, "#header-tabs")
      assert has_element?(view, "#header-context-menu #workspace-filters-positioner[phx-hook=Floating]")
      refute has_element?(view, "#main-content #library-search")
      refute has_element?(view, "#main-content #notebook-search")
      refute has_element?(view, "#main-content #word-search")
      assert has_element?(view, "#app-header #workspace-menu")
      assert has_element?(view, "#workspace-menu a[href='/pages']")
      assert has_element?(view, "#workspace-menu a[href='/pages/new']")
      refute has_element?(view, "#workspace-menu a[href='/vocabulary']")
      assert has_element?(view, "#workspace-menu a[href='/notebook']")
      assert has_element?(view, "##{active}[aria-current=page]")
      assert has_element?(view, "#app-header #account-menu-trigger")
      refute has_element?(view, "#workspace-menu #account-menu")
      refute has_element?(view, "#workspace-menu a[href='/write']")
      refute has_element?(view, "#workspace-menu a[href='/review']")
    end
  end

  test "creates multiple pages and renders Markdown without a bottom question bar", %{conn: conn, scope: scope} do
    {:ok, editor, _} = live(conn, ~p"/pages/new")
    assert has_element?(editor, "#header-context-menu #page-save[type=submit][form=page-form].workspace-header-primary")
    refute has_element?(editor, "#page-form #page-save")
    refute has_element?(editor, "#page-editor-status")
    refute has_element?(editor, ".page-save-row")

    render_submit(editor, "save", %{
      "page" => %{"title" => "My first page", "body" => "## A heading\n\nA **wonderful** sentence."}
    })

    assert has_element?(editor, "#page-close[href='/pages']")
    assert has_element?(editor, ".reader-header .context-title", "My first page")
    assert has_element?(editor, "#header-context-menu #page-notebook")
    assert has_element?(editor, ".header-actions #account-menu-trigger")
    refute has_element?(editor, "#workspace-menu")
    refute has_element?(editor, "#brand-home")
    refute has_element?(editor, "#page-save")
    assert has_element?(editor, "#page-reading h2", "A heading")
    assert has_element?(editor, "#page-reading strong", "wonderful")
    refute has_element?(editor, "#reading-toolbar")
    {:ok, second, _} = live(conn, ~p"/pages/new")
    render_submit(second, "save", %{"page" => %{"title" => "My second page", "body" => ""}})
    assert length(Leitor.Library.list_texts(scope)) == 2
    render_click(second, "edit")
    assert has_element?(second, "#page-editor")
    assert has_element?(second, "#header-context-menu #page-save[form=page-form]")
  end

  test "only successful owned saves clear the corresponding tab draft and refresh reading revision", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/pages/new")
    new_key = "#{scope.user.id}:new"
    assert has_element?(view, ~s(#page-editor[data-draft-key="#{new_key}"]))

    render_submit(view, "save", %{"page" => %{"title" => "", "body" => "Keep the draft."}})
    refute_push_event(view, "page-saved", %{})
    assert has_element?(view, "#page-editor")

    render_submit(view, "save", %{"page" => %{"title" => "A thought", "body" => "Keep the draft."}})
    assert_push_event(view, "page-saved", %{key: ^new_key})
    [page] = Leitor.Library.list_texts(scope)
    page_key = "#{scope.user.id}:#{page.id}"
    revision = Base.encode16(:crypto.hash(:sha256, page.body), case: :lower)
    assert has_element?(view, ~s(#page-reading[data-reading-key="#{page_key}"][data-reading-version="#{revision}"]))

    render_click(view, "edit")
    assert has_element?(view, ~s(#page-editor[data-draft-key="#{page_key}"]))
    render_submit(view, "save", %{"page" => %{"title" => "A thought", "body" => "An updated thought."}})
    assert_push_event(view, "page-saved", %{key: ^page_key})
    refute has_element?(view, ~s(#page-reading[data-reading-version="#{revision}"]))
    assert has_element?(view, "#page-reading", "An updated thought.")
  end

  test "imported texts open in the page reader and keep reading preferences", %{conn: conn, scope: scope} do
    {:ok, page} =
      Leitor.Library.create_text(scope, %{title: "An imported chapter", body: "A wonderful sentence.", source: "import"})

    {:ok, library, _} = live(conn, ~p"/pages")
    assert has_element?(library, "a[href='/pages/#{page.id}']", "An imported chapter")

    conn = put_connect_params(conn, %{"reading_preferences" => %{"face" => "sans", "size" => 27, "numbers" => true}})
    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")
    assert has_element?(view, ".free-page.page-face-sans.page-size-27")
    refute has_element?(view, ".free-page.hide-paragraph-numbers")
    assert has_element?(view, "#reading-paragraph-numbers[aria-checked=true]")
    render_click(view, "reading-face", %{"face" => "serif"})
    assert_push_event(view, "reading-preference", %{key: "face", value: "serif"})
    render_click(view, "reading-size", %{"size" => "19"})
    assert_push_event(view, "reading-preference", %{key: "size", value: 19})
    assert has_element?(view, ".free-page.page-face-serif.page-size-19")
    refute has_element?(view, "#reading-appearance[open]")
    render_click(view, "shortcuts")
    assert has_element?(view, "#page-shortcut-dialog", "Open or close your notebook")
  end

  test "paragraph numbers start hidden and the appearance switch persists both choices", %{conn: conn, scope: scope} do
    {:ok, page} =
      Pages.create_page(scope, %{"title" => "Quiet reading", "body" => "First paragraph.\n\nSecond paragraph."})

    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")
    assert has_element?(view, ".free-page.hide-paragraph-numbers")
    assert has_element?(view, "#page-block-1", "Second paragraph.")
    assert has_element?(view, "#reading-paragraph-numbers[role=switch][aria-checked=false]")

    view |> element("#reading-paragraph-numbers") |> render_click()
    assert_push_event(view, "reading-preference", %{key: "numbers", value: true})
    refute has_element?(view, ".free-page.hide-paragraph-numbers")
    assert has_element?(view, "#reading-paragraph-numbers[aria-checked=true]")

    view |> element("#reading-paragraph-numbers") |> render_click()
    assert_push_event(view, "reading-preference", %{key: "numbers", value: false})
    assert has_element?(view, ".free-page.hide-paragraph-numbers")

    for value <- [false, "true", 1, nil] do
      conn = put_connect_params(conn, %{"reading_preferences" => %{"numbers" => value}})
      {:ok, reopened, _} = live(conn, ~p"/pages/#{page.id}")
      assert has_element?(reopened, ".free-page.hide-paragraph-numbers")
    end
  end

  test "appearance tabs apply continuous text sizes, validate bounds and reset only typography", %{
    conn: conn,
    scope: scope
  } do
    {:ok, page} = Pages.create_page(scope, %{"title" => "Typography", "body" => "A readable paragraph."})
    conn = put_connect_params(conn, %{"reading_preferences" => %{"size" => 20, "numbers" => true}})
    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")
    assert has_element?(view, ".free-page[style='--page-text-size:20px']")
    view |> element("#appearance-tab-text") |> render_click()
    assert has_element?(view, "#appearance-tab-text[aria-selected=true]")
    refute has_element?(view, "#appearance-panel-text[hidden]")

    view |> form("#reading-size-form", %{"size" => "28"}) |> render_change()
    assert_push_event(view, "reading-preference", %{key: "size", value: 28})
    assert has_element?(view, "#reading-size-larger[disabled]")
    render_click(view, "reading-size", %{"size" => "15"})
    assert_push_event(view, "reading-preference", %{key: "size", value: 15})
    assert has_element?(view, "#reading-size-smaller[disabled]")

    for invalid <- ["14", "29", "23px", "bad"] do
      render_click(view, "reading-size", %{"size" => invalid})
      assert has_element?(view, "#reading-size-value", "15")
    end

    view |> element("#font-sans") |> render_click()
    view |> element("#reading-text-reset") |> render_click()
    assert_push_event(view, "reading-preference", %{key: "face", value: "serif"})
    assert_push_event(view, "reading-preference", %{key: "size", value: 20})
    assert has_element?(view, "#font-serif[aria-pressed=true]")
    assert has_element?(view, "#reading-paragraph-numbers[aria-checked=true]")
    refute has_element?(view, "#reading-text-reset")
  end

  test "all appearance settings validate saved values, persist changes and preserve non-text choices on reset", %{
    conn: conn,
    scope: scope
  } do
    {:ok, page} = Pages.create_page(scope, %{"title" => "Appearance", "body" => "First paragraph.\n\nSecond paragraph."})

    saved = %{
      "face" => "book",
      "pen" => "cobalt",
      "leading" => "loose",
      "width" => "wide",
      "align" => "justify",
      "paras" => "indented",
      "rail" => false,
      "focus" => true
    }

    conn = put_connect_params(conn, %{"reading_preferences" => saved})
    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")

    assert has_element?(
             view,
             ".free-page.page-face-book.page-width-wide.page-leading-loose.page-align-justify.page-paras-indented.hide-page-map"
           )

    refute has_element?(view, ".page-focus-mode")
    assert has_element?(view, "#reading-pen-cobalt[aria-pressed=true]")
    assert has_element?(view, "#reading-rail[aria-checked=false]")

    view |> element("#reading-focus") |> render_click()
    assert has_element?(view, ".page-focus-mode")
    assert has_element?(view, "#reading-focus[aria-checked=true]")
    view |> element("#reading-focus") |> render_click()
    refute has_element?(view, ".page-focus-mode")

    for face <- ~w(serif book sans legible) do
      render_click(view, "reading-face", %{"face" => face})
      assert_push_event(view, "reading-preference", %{key: "face", value: ^face})
      assert has_element?(view, "#font-#{face}[aria-pressed=true]")
    end

    for {key, value} <- [
          {"leading", "tight"},
          {"width", "narrow"},
          {"align", "left"},
          {"paras", "spaced"},
          {"pen", "moss"},
          {"rail", true}
        ] do
      id = if key == "rail", do: "reading-rail", else: "reading-#{key}-#{value}"
      view |> element("##{id}") |> render_click()
      assert_push_event(view, "reading-preference", %{key: ^key, value: ^value})
    end

    for {key, value} <- [{"pen", "injected"}, {"rail", "unknown"}, {"unknown", "wide"}] do
      render_click(view, "reading-option", %{"key" => key, "value" => value})
      assert has_element?(view, "#reading-pen-moss[aria-pressed=true]")
      assert has_element?(view, "#reading-rail[aria-checked=true]")
    end

    render_click(view, "reading-text-reset")
    assert has_element?(view, ".page-leading-normal.page-width-normal.page-align-left.page-paras-spaced")
    assert has_element?(view, "#reading-pen-moss[aria-pressed=true]")
    assert has_element?(view, "#reading-rail[aria-checked=true]")

    assert_push_event(view, "reading-text-preferences-reset", %{
      "leading" => "normal",
      "width" => "normal",
      "align" => "left",
      "paras" => "spaced"
    })

    bad =
      put_connect_params(conn, %{
        "reading_preferences" => %{"face" => "bad", "leading" => %{}, "pen" => "bad", "rail" => "false"}
      })

    {:ok, safe, _} = live(bad, ~p"/pages/#{page.id}")
    assert has_element?(safe, ".page-face-serif.page-leading-normal")
    assert has_element?(safe, "#reading-pen-vermilion[aria-pressed=true]")
    assert has_element?(safe, "#reading-rail[aria-checked=true]")
  end

  test "highlights, notes, definitions and jars persist and notebook filters by type", %{conn: conn, scope: scope} do
    {:ok, page} = Pages.create_page(scope, %{"title" => "Reading", "body" => "A wonderful sentence."})
    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")
    anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11}
    render_hook(view, "select", anchor)
    assert has_element?(view, "#page-selection")
    refute has_element?(view, "#selection-highlight")
    refute has_element?(view, ".selection-palette")
    render_click(view, "highlight", %{"color" => "yellow"})
    assert [%{kind: "highlight", quote: "wonderful"}] = Pages.list_marks(scope, page.id)
    render_hook(view, "select", anchor)
    render_click(view, "selection-mode", %{"mode" => "note"})
    render_submit(view, "note", %{"note" => %{"body" => "A lovely word."}})
    render_hook(view, "select", anchor)
    render_click(view, "help", %{"action" => "define"})
    assert render_async(view) =~ "Very good or pleasing."
    note = Enum.find(Pages.list_marks(scope, page.id), &(&1.kind == "note"))
    render_click(view, "edit-note", %{"id" => note.id})
    render_submit(view, "note", %{"note" => %{"body" => "A lovely word, worth keeping."}})
    assert Pages.get_mark!(scope, note.id).body == "A lovely word, worth keeping."
    render_click(view, "export-notebook", %{"mode" => "download"})
    assert_push_event(view, "page-export", %{mode: "download", markdown: markdown})
    assert markdown =~ "A lovely word, worth keeping."
    render_click(view, "notebook")
    assert has_element?(view, "#page-notebook-panel")
    render_click(view, "filter-notebook", %{"kind" => "definition"})
    assert has_element?(view, "#page-notebook-marks", "Very good or pleasing.")
    refute has_element?(view, "#page-notebook-marks", "A lovely word, worth keeping.")
    definition = Enum.find(Pages.list_marks(scope, page.id), &(&1.kind == "definition"))
    render_click(view, "mark-to-pot", %{"id" => definition.id})
    render_submit(view, "save-pot", %{"pot" => %{"meaning" => "maravilhoso", "category" => "adj"}})
    assert [%{term: "wonderful", category: "adj"}] = Learning.list_entries(scope)
    {:ok, reopened, _} = live(conn, ~p"/pages/#{page.id}")
    render_click(reopened, "notebook")
    assert has_element?(reopened, "#page-notebook-marks", "A lovely word, worth keeping.")
    render_click(reopened, "remove-mark", %{"id" => definition.id})
    assert length(Pages.list_marks(scope, page.id)) == 2
  end

  test "margin cards open from the source, collapse, keep follow-ups and export the conversation", %{
    conn: conn,
    scope: scope
  } do
    {:ok, page} = Pages.create_page(scope, %{"title" => "Reading", "body" => "A wonderful sentence."})
    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")
    render_hook(view, "select", %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11})
    render_click(view, "help", %{"action" => "define"})
    assert render_async(view) =~ "Very good or pleasing."
    [mark] = Pages.list_marks(scope, page.id)
    assert has_element?(view, "[data-margin-mark='#{mark.id}'].is-active")
    render_click(view, "collapse-mark")
    assert has_element?(view, "[data-margin-mark='#{mark.id}'].is-collapsed")
    render_hook(view, "activate-mark", %{"id" => mark.id})
    render_submit(view, "follow-up", %{"id" => mark.id, "follow" => %{"question" => "em português"}})
    render_async(view)
    assert [%{question: "em português"}] = Pages.get_mark!(scope, mark.id).replies
    assert has_element?(view, ".page-follow-turn", "em português")
    render_click(view, "retry-mark", %{"id" => mark.id})
    render_async(view)
    assert length(Pages.get_mark!(scope, mark.id).replies) == 1
    render_click(view, "export-notebook", %{"mode" => "download"})
    assert_push_event(view, "page-export", %{markdown: markdown})
    assert markdown =~ "em português"
    {:ok, reopened, _} = live(conn, ~p"/pages/#{page.id}")
    render_hook(reopened, "activate-mark", %{"id" => mark.id})
    assert has_element?(reopened, ".page-follow-turn", "em português")
    render_submit(reopened, "follow-up", %{"id" => mark.id, "follow" => %{"question" => " "}})
    assert render(reopened) =~ "Ask up to 500 characters"
  end

  test "the waiting card can be stopped without losing the page or saving an unfinished answer", %{
    conn: conn,
    scope: scope
  } do
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageGate)
    Application.put_env(:leitor, :language_test_owner, self())
    on_exit(fn -> Application.delete_env(:leitor, :language_test_owner) end)
    {:ok, page} = Pages.create_page(scope, %{"title" => "Reading", "body" => "A wonderful sentence."})
    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")
    render_hook(view, "select", %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11})
    render_click(view, "help", %{"action" => "define"})
    assert_receive {:language_started, task}
    monitor = Process.monitor(task)
    assert has_element?(view, "#page-pending-card [role='status'][aria-label='Writing']")
    render_click(view, "stop-help")
    assert_receive {:DOWN, ^monitor, :process, ^task, _reason}
    refute has_element?(view, "#page-pending-card")
    refute has_element?(view, "#page-help-error")
    assert Pages.list_marks(scope, page.id) == []
    assert Pages.get_page!(scope, page.id).body == "A wonderful sentence."
  end

  test "all reading actions stream safe previews before saving a complete annotation", %{conn: conn, scope: scope} do
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageGate)
    Application.put_env(:leitor, :language_test_owner, self())
    on_exit(fn -> Application.delete_env(:leitor, :language_test_owner) end)
    {:ok, page} = Pages.create_page(scope, %{"title" => "Reading", "body" => "A wonderful sentence."})

    for action <- ~w(define explain simplify ask) do
      {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")
      count = length(Pages.list_marks(scope, page.id))
      render_hook(view, "select", %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11})
      render_click(view, "help", %{"action" => action, "question" => %{"question" => "Why?"}})
      assert_receive {:language_started, task}
      html = reading_fragment(view, task, ~S({"answer":"**A clear idea.** [¶1]))
      assert html =~ "<strong>A clear idea.</strong>"
      assert has_element?(view, "#page-pending-card .page-answer a[href='#page-block-0']")
      refute has_element?(view, "#page-pending-card .page-writing")
      assert length(Pages.list_marks(scope, page.id)) == count
      reading_fragment(view, task, ~S|\n<script>unsafe()</script>","meaning":"Private metadata","category":"word"}|)
      refute has_element?(view, "#page-pending-card script")
      refute has_element?(view, "#page-pending-card", "Private metadata")
      send(task, {:complete, {:ok, %{"answer" => "**A clear idea.** [¶1]", "meaning" => "ideia", "category" => "word"}}})
      render_async(view)
      refute has_element?(view, "#page-pending-card")
      assert length(Pages.list_marks(scope, page.id)) == count + 1
    end
  end

  test "follow-up and retry previews preserve saved answers on stop or failure", %{conn: conn, scope: scope} do
    {:ok, page} = Pages.create_page(scope, %{"title" => "Reading", "body" => "A wonderful sentence."})
    {:ok, view, _} = live(conn, ~p"/pages/#{page.id}")
    render_hook(view, "select", %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11})
    render_click(view, "help", %{"action" => "define"})
    render_async(view)
    [mark] = Pages.list_marks(scope, page.id)
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageGate)
    Application.put_env(:leitor, :language_test_owner, self())
    on_exit(fn -> Application.delete_env(:leitor, :language_test_owner) end)
    render_submit(view, "follow-up", %{"id" => mark.id, "follow" => %{"question" => "em português"}})
    assert_receive {:language_started, follow}
    reading_fragment(view, follow, ~S({"answer":"Uma **ideia**))
    assert has_element?(view, ".page-follow-pending", "em português")
    assert has_element?(view, ".page-follow-pending strong", "ideia")
    assert has_element?(view, ".page-card-expanded .page-answer", mark.body)
    assert Pages.get_mark!(scope, mark.id).replies == []
    monitor = Process.monitor(follow)
    render_click(view, "stop-help")
    assert_receive {:DOWN, ^monitor, :process, ^follow, _}
    refute has_element?(view, ".page-follow-pending")
    assert Pages.get_mark!(scope, mark.id).body == mark.body

    render_click(view, "retry-mark", %{"id" => mark.id})
    assert_receive {:language_started, retry}
    reading_fragment(view, retry, ~S({"answer":"A replacement answer))
    assert has_element?(view, ".page-card-expanded .page-answer", "A replacement answer")
    assert Pages.get_mark!(scope, mark.id).body == mark.body
    send(retry, {:complete, {:error, :invalid_response}})
    render_async(view)
    assert has_element?(view, ".page-card-expanded .page-answer", mark.body)
    refute has_element?(view, ".page-card-expanded", "A replacement answer")
    assert Pages.get_mark!(scope, mark.id).replies == []
  end

  defp reading_fragment(view, task, fragment) do
    send(task, {:delta, fragment})
    assert_receive {:language_delta, {:help_fragment, id, ^fragment}}
    send(view.pid, {:flush_help, id})
    render(view)
  end
end
