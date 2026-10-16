defmodule LeitorWeb.NotebookRedirectController do
  use LeitorWeb, :controller

  def words(conn, _params), do: redirect(conn, to: ~p"/notebook?view=words")
end
