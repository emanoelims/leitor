defmodule LeitorWeb.HealthController do
  use LeitorWeb, :controller

  def show(conn, _params) do
    case Leitor.Repo.query("SELECT 1", [], timeout: 2_000) do
      {:ok, _result} -> json(conn, %{status: "ok"})
      {:error, _reason} -> conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  end
end
