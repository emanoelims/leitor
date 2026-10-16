defmodule LeitorWeb.UserLive.LoginTest do
  use LeitorWeb.ConnCase, async: true

  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.Accounts

  test "offers only email-link login with no public reading", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")
    assert has_element?(view, "#login_form_magic")
    refute has_element?(view, "input[type=password]")
    refute has_element?(view, "#login_form_password")
    refute has_element?(view, "a[href='/read']")
  end

  test "sends a link for existing readers without enumerating accounts or registering strangers", %{conn: conn} do
    existing = user_fixture()

    for email <- [existing.email, "new-reader@example.com"] do
      {:ok, view, _} = live(conn, ~p"/users/log-in")

      {:ok, _, html} =
        view
        |> form("#login_form_magic", user: %{email: email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is valid"
      user = Accounts.get_user_by_email(email)

      if email == existing.email do
        assert user
        assert Leitor.Repo.get_by!(Leitor.Accounts.UserToken, user_id: user.id).context == "login"
      else
        refute user
      end
    end
  end

  test "invalid email creates no account", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/users/log-in")
    render_submit(view, "submit_magic", %{"user" => %{"email" => "invalid"}})
    refute Accounts.get_user_by_email("invalid")
  end

  test "sudo reauthentication uses the current account email", %{conn: conn} do
    user = user_fixture()
    {:ok, view, html} = live(log_in_user(conn, user), ~p"/users/log-in")
    assert html =~ "You need to reauthenticate"
    assert has_element?(view, "input[type=email][readonly][value='#{user.email}']")
  end
end
