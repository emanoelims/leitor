defmodule LeitorWeb.PageController do
  use LeitorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
