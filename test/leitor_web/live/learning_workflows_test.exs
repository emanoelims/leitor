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

  test "the private library validates imports, filters live updates, and deletes only owned texts", %{
    conn: conn,
    scope: scope
  } do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/pages")
    {:ok, view, _} = live(conn, ~p"/pages")
    view |> element("#open-page-import") |> render_click()
    view |> form("#material-form", material: %{body: ""}) |> render_submit()
    assert render(view) =~ "can&#39;t be blank"
    view |> form("#material-form", material: %{body: "# A chapter\n\nHello world."}) |> render_change()
    view |> form("#material-form", material: %{body: "# A chapter\n\nHello world."}) |> render_submit()
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

  test "word edits and status changes refresh filtered jars without losing other records", %{conn: conn, scope: scope} do
    {:ok, first} = Learning.save_word(scope, %{term: "has", meaning: "tem", category: "aux", context: "She has a book."})

    {:ok, _} =
      Learning.save_word(scope, %{term: "London", meaning: "Londres", category: "proper", context: "London is a city."})

    {:ok, view, _} = live(conn, ~p"/notebook?view=words")
    render_click(view, "word-category", %{"category" => "verb"})
    assert render(view) =~ "has"
    refute has_element?(view, ".jar-words button", "London")
    render_click(view, "hide-empty")
    render_click(view, "open", %{"id" => first.id})
    render_submit(view, "edit", %{"entry" => %{"meaning" => "possesses", "category" => "verb"}})
    assert Learning.get_entry!(scope, first.id).meaning == "possesses"
    render_click(view, "known", %{"id" => first.id})
    render_click(view, "word-category", %{"category" => "known"})
    assert has_element?(view, ".jar-words button", "has")
    render_click(view, "delete", %{"id" => first.id})
    refute has_element?(view, ".jar-words button")
    assert [%{term: "london"}] = Learning.list_entries(scope)
  end
end
