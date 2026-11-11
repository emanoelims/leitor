defmodule LeitorWeb.SharedFigureController do
  use LeitorWeb, :controller

  def show(conn, %{"token" => token, "id" => id}) do
    conn =
      conn |> put_resp_header("cache-control", "private, no-store") |> put_resp_header("referrer-policy", "no-referrer")

    case Leitor.Sharing.figure(conn.assigns.current_scope, token, id) do
      {:ok, payload} -> json(conn, %{payload | bundle: Base.encode64(payload.bundle)})
      {:error, :unavailable} -> send_resp(conn, 404, "Not found")
    end
  end

  def sign_in(conn, %{"token" => token}) do
    if Regex.match?(~r/^[A-Za-z0-9_-]{43}$/, token) do
      conn |> put_session(:user_return_to, ~p"/s/#{token}") |> redirect(to: ~p"/users/log-in")
    else
      send_resp(conn, 404, "Not found")
    end
  end
end
