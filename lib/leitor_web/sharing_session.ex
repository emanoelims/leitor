defmodule LeitorWeb.SharingSession do
  @moduledoc "Assigns an anonymous browser identity in a signed HttpOnly cookie; it never authenticates an account."
  import Plug.Conn

  @cookie "_leitor_visitor"
  def init(options), do: options

  def call(conn, _options) do
    conn = fetch_cookies(conn, signed: [@cookie])

    id =
      case Ecto.UUID.cast(conn.cookies[@cookie]) do
        {:ok, id} -> id
        :error -> Ecto.UUID.generate()
      end

    conn =
      if String.starts_with?(conn.request_path, "/s/") do
        conn
        |> put_resp_header("referrer-policy", "no-referrer")
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> put_resp_header("cache-control", "private, no-store")
      else
        conn
      end

    conn
    |> put_resp_cookie(@cookie, id,
      sign: true,
      http_only: true,
      secure: conn.scheme == :https,
      same_site: "Lax",
      max_age: 2_592_000
    )
    |> put_session(:visitor_id, id)
  end
end
