defmodule LeitorWeb.BookAssetController do
  @moduledoc """
  Serves the images of imported books.

  Images are private to the book's reader. A shared chapter exposes only its own book's images, through the
  share token, and never to a reader whose access has been revoked.
  """
  use LeitorWeb, :controller

  alias Leitor.Library
  alias Leitor.Sharing

  @doc "Serves an image of a book the signed-in reader owns."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    case Library.get_book_asset(conn.assigns.current_scope, id) do
      {:ok, asset} -> send_image(conn, asset)
      :error -> send_resp(conn, 404, "Not found")
    end
  end

  @doc "Serves an image of the book behind a shared chapter."
  @spec shared(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def shared(conn, %{"token" => token, "id" => id}) do
    case Sharing.book_asset(conn.assigns.current_scope, token, id) do
      {:ok, asset} -> send_image(conn, asset)
      {:error, :unavailable} -> send_resp(conn, 404, "Not found")
    end
  end

  # Ids never change what they point to, so browsers may keep the bytes; `sandbox` stops a directly opened
  # image from running anything.
  defp send_image(conn, asset) do
    conn
    |> put_resp_content_type(asset.content_type, nil)
    |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("etag", ~s("#{Base.encode16(asset.digest, case: :lower)}"))
    |> send_resp(200, asset.data)
  end
end
