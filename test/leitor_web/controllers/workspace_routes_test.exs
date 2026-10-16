defmodule LeitorWeb.WorkspaceRoutesTest do
  use LeitorWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "old word jars links open the combined notebook", %{conn: conn} do
    assert conn |> get(~p"/vocabulary") |> redirected_to() == ~p"/users/log-in"
    scope = Leitor.AccountsFixtures.user_scope_fixture()
    conn = log_in_user(conn, scope.user)
    assert conn |> get(~p"/vocabulary") |> redirected_to() == ~p"/notebook?view=words"
  end

  test "retired screens have no route, including nested resource paths" do
    for path <-
          [
            "/reader",
            "/read",
            "/read/example",
            "/library",
            "/lessons",
            "/lessons/example",
            "/review",
            "/write",
            "/practice",
            "/progress",
            "/rooms",
            "/rooms/example",
            "/dev/componentes"
          ] ++
            for(
              resource <- ["manage/rooms", "texts", "entries", "attempts"],
              suffix <- ["", "/new", "/example", "/example/edit"],
              do: "/" <> resource <> suffix
            ) do
      assert build_conn() |> get(path) |> response(404)
    end
  end
end
