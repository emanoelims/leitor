defmodule LeitorWeb.FigureController do
  use LeitorWeb, :controller

  alias Leitor.Figures.Artifacts

  def show(conn, %{"id" => id}) do
    case Artifacts.get_ready(conn.assigns.current_scope, id) do
      nil ->
        send_resp(conn, 404, "Not found")

      artifact ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> json(%{
          bundle: Base.encode64(artifact.bundle),
          style: artifact.style,
          custom_style: Map.get(artifact.source, "css", ""),
          digest: artifact.digest
        })
    end
  end
end
