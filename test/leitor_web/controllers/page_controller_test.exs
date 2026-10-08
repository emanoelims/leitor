defmodule LeitorWeb.PageControllerTest do
  use LeitorWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "What shall we"
  end
end
