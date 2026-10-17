defmodule LeitorWeb.FigureControllerTest do
  use LeitorWeb.ConnCase, async: true

  import Leitor.AccountsFixtures

  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Artifacts

  test "artifact loading requires login", %{conn: conn} do
    assert conn |> get(~p"/figures/#{Ecto.UUID.generate()}") |> redirected_to() == ~p"/users/log-in"
  end

  test "only the owner may load a reviewed executable artifact", %{conn: conn} do
    user = user_fixture()

    attrs = %{
      title: "Lock",
      caption: "Study",
      model: "test",
      source: %{},
      report: %{},
      status: "ready",
      bundle: "code",
      style: "css",
      digest: "digest",
      preview: <<137, 80, 78, 71>>
    }

    {:ok, artifact} = Artifacts.store(Scope.for_user(user), attrs)
    own = conn |> put_req_header("accept", "application/json") |> log_in_user(user) |> get(~p"/figures/#{artifact.id}")
    assert json_response(own, 200)["bundle"] == Base.encode64("code")
    assert get_resp_header(own, "cache-control") == ["private, no-store"]
    foreign = conn |> log_in_user(user_fixture()) |> get(~p"/figures/#{artifact.id}")
    assert response(foreign, 404) == "Not found"
    {:ok, draft} = Artifacts.store(Scope.for_user(user), %{attrs | status: "draft", bundle: nil})
    assert conn |> log_in_user(user) |> get(~p"/figures/#{draft.id}") |> response(404) == "Not found"
  end
end
