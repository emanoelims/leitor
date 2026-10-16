defmodule LeitorWeb.HealthControllerTest do
  use LeitorWeb.ConnCase

  test "readiness is public and checks the database without creating a session", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "set-cookie") == []
  end
end
