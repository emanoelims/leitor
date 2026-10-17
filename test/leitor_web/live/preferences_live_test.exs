defmodule LeitorWeb.PreferencesLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.Accounts
  alias Leitor.Pages

  setup do
    on_exit(fn -> Gettext.put_locale(LeitorWeb.Gettext, "en") end)
    :ok
  end

  test "preferences require login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/settings")
  end

  test "preferences remain available outside sudo mode and public pages remember the locale", %{conn: conn} do
    scope = user_scope_fixture()

    stale_conn =
      log_in_user(conn, scope.user, token_authenticated_at: DateTime.shift(DateTime.utc_now(:second), minute: -11))

    assert {:ok, _, _} = live(stale_conn, ~p"/settings")
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(stale_conn, ~p"/users/settings")
    portuguese = conn |> put_req_cookie("leitor_locale", "pt_BR") |> get(~p"/users/log-in")
    assert portuguese.resp_body =~ ~s(lang="pt-BR")
    assert portuguese.resp_body =~ "Entrar com e-mail"
    english = build_conn() |> put_req_cookie("leitor_locale", "unsupported") |> get(~p"/users/log-in")
    assert english.resp_body =~ ~s(lang="en")
  end

  test "invalid changes stay on the form and valid choices survive reload", %{conn: conn} do
    scope = user_scope_fixture()
    {:ok, _} = Leitor.AI.put_credential(scope, %{provider: "anthropic", api_key: "test-preferences-own-key"})
    conn = log_in_user(conn, scope.user)
    {:ok, view, _} = live(conn, ~p"/settings")
    assert has_element?(view, "#preferences-locale option[value=en][selected]")
    assert has_element?(view, "#account-preferences[href='/settings']")

    render_change(view, "validate", %{"user" => %{"preferences" => %{"locale" => "xx"}}})
    assert render(view) =~ "is invalid"
    render_submit(view, "save", %{"user" => %{"preferences" => %{"locale" => "xx"}}})
    assert render(view) =~ "is invalid"
    assert Accounts.get_preferences(scope).locale == "en"

    view
    |> form("#preferences-form",
      user: %{
        preferences: %{
          locale: "pt_BR",
          ai_locale: "en",
          reading_model: "anthropic:claude-opus-5-5",
          writing_model: "anthropic:claude-sonnet-5-5"
        }
      }
    )
    |> render_submit()

    assert_redirect(view, ~p"/settings")
    {:ok, reopened, html} = live(conn, ~p"/settings")
    assert html =~ "Idioma da aplicação"
    assert has_element?(reopened, "#preferences-locale option[value=pt_BR][selected]")
    assert has_element?(reopened, "#preferences-ai-locale option[value=en][selected]")
    assert has_element?(reopened, "#preferences-reading-model option[value='anthropic:claude-opus-5-5'][selected]")
    assert has_element?(reopened, "#preferences-writing-model option[value='anthropic:claude-sonnet-5-5'][selected]")
  end

  test "account language overrides browser locale and preserves page content", %{conn: conn} do
    scope = user_scope_fixture()
    {:ok, _} = Accounts.update_preferences(scope, %{locale: "pt_BR"})
    {:ok, page} = Pages.create_page(scope, %{"title" => "Notebook", "body" => "Original English text."})
    conn = log_in_user(conn, scope.user)
    {:ok, view, _} = conn |> put_connect_params(%{"locale" => "en"}) |> live(~p"/pages")
    assert render(view) =~ "Páginas"
    assert has_element?(view, "#library-texts h2", "Notebook")
    other = user_scope_fixture()
    english_conn = build_conn() |> log_in_user(other.user) |> get(~p"/pages")
    assert english_conn.resp_body =~ ~s(lang="en")
    assert get(conn, ~p"/pages").resp_body =~ ~s(lang="pt-BR")
    {:ok, reader, html} = live(conn, ~p"/pages/#{page.id}")
    assert html =~ "Original English text."
    assert has_element?(reader, "#account-preferences", "Preferências")
  end

  test "shared accounts see Haiku only and keys are never echoed, including invalid submissions", %{conn: conn} do
    scope = user_scope_fixture()
    {:ok, view, html} = live(log_in_user(conn, scope.user), ~p"/settings")
    refute html =~ "option value=\"anthropic:claude-opus"
    refute has_element?(view, "#preferences-reading-model option[value='anthropic:claude-opus-5-5']")
    assert has_element?(view, "#ai-account-allowance", "0 / 20")
    key = "test-own-account-key-1234"
    render_submit(view, "save-key", %{"credential" => %{"provider" => "anthropic", "api_key" => key}})
    refute render(view) =~ key
    assert has_element?(view, "#ai-key-value[value='']")
    assert has_element?(view, "#preferences-reading-model option[value='anthropic:claude-opus-5-5']")
    [credential] = Leitor.AI.credentials(scope)
    render_submit(view, "save-key", %{"credential" => %{"provider" => "bad", "api_key" => key}})
    refute render(view) =~ key
    render_click(view, "delete-key", %{"id" => credential.id})
    assert Leitor.AI.credentials(scope) == []
    refute has_element?(view, "#preferences-reading-model option[value='anthropic:claude-opus-5-5']")
  end

  test "changing provider keys requires recent authentication but reading preferences does not", %{conn: conn} do
    scope = user_scope_fixture()
    stale = log_in_user(conn, scope.user, token_authenticated_at: DateTime.shift(DateTime.utc_now(:second), minute: -21))
    {:ok, view, _} = live(stale, ~p"/settings")

    render_submit(view, "save-key", %{"credential" => %{"provider" => "anthropic", "api_key" => "test-stale-account-key"}})

    assert_redirect(view, ~p"/users/log-in")
    assert Leitor.AI.credentials(scope) == []
    {:ok, metadata} = Leitor.AI.put_credential(scope, %{provider: "anthropic", api_key: "test-stale-account-key"})
    {:ok, view, _} = live(stale, ~p"/settings")
    render_click(view, "delete-key", %{"id" => metadata.id})
    assert_redirect(view, ~p"/users/log-in")
    assert Leitor.AI.credentials(scope) != []
  end
end
