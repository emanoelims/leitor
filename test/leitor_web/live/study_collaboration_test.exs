defmodule LeitorWeb.StudyCollaborationTest do
  use LeitorWeb.ConnCase

  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.Accounts.Scope
  alias Leitor.Study

  test "requires authentication for all collaboration routes", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/rooms")
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/rooms/unknown")
  end

  test "two readers follow the host, exchange messages, and leave when the room closes", %{conn: conn} do
    host = user_fixture()
    guest = user_fixture()
    scope = Scope.for_user(host)
    {:ok, room} = Study.open_room(scope, %{"title" => "Reading club", "body" => "First sentence. Second sentence."})
    host_conn = log_in_user(conn, host)
    guest_conn = log_in_user(build_conn(), guest)
    {:ok, host_view, _} = live(host_conn, ~p"/rooms/#{room.invite_code}")
    {:ok, guest_view, _} = live(guest_conn, ~p"/rooms/#{room.invite_code}")
    assert has_element?(host_view, "#shared-sentence", "First sentence.")
    assert has_element?(guest_view, "#room-next[disabled]")
    assert {:error, :forbidden} = Study.advance_room(Scope.for_user(guest), room.invite_code, :next)
    host_view |> element("#room-next") |> render_click()
    assert has_element?(guest_view, "#shared-sentence", "Second sentence.")
    guest_view |> form("#message-form", message: %{body: "What does this mean?"}) |> render_submit()
    assert render(host_view) =~ "What does this mean?"
    refute render(host_view) =~ guest.email
    {:ok, _} = Study.update_room(scope, Study.get_room!(scope, room.id), %{body: "Revised sentence."})
    assert has_element?(guest_view, "#shared-sentence", "Revised sentence.")
    assert has_element?(host_view, "#shared-sentence", "Revised sentence.")
    {:ok, _} = Study.delete_room(scope, Study.get_room!(scope, room.id))
    assert_redirect(host_view, ~p"/rooms")
    assert_redirect(guest_view, ~p"/rooms")
    assert {:error, :not_found} = Study.join_room(Scope.for_user(guest), room.invite_code)
  end

  test "lobby creates invitations and rejects unknown invitations", %{conn: conn} do
    {:ok, view, _} = live(log_in_user(conn, user_fixture()), ~p"/rooms")
    view |> form("#join-room-form", invitation: %{code: "missing"}) |> render_submit()
    assert render(view) =~ "This invitation is unavailable"
    view |> form("#room-form", room: %{title: "Our room", body: "One sentence."}) |> render_submit()
    {path, _flash} = assert_redirect(view)
    assert path =~ "/rooms/"
  end
end
