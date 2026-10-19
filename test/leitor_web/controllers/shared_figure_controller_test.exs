defmodule LeitorWeb.SharedFigureControllerTest do
  use LeitorWeb.ConnCase, async: true

  import Leitor.AccountsFixtures

  alias Leitor.Figures.Artifacts
  alias Leitor.Pages
  alias Leitor.Sharing

  test "a guest receives only the embedded accepted payload and revocation applies to the next fetch", %{conn: conn} do
    owner = user_scope_fixture()

    {:ok, artifact} =
      Artifacts.store(owner, %{
        title: "Lock",
        caption: "Test",
        model: "test",
        source: %{"css" => "svg{}", "secret" => "private author source"},
        report: %{"secret" => true},
        status: "ready",
        bundle: "program",
        style: "css",
        preview: <<137, 80, 78, 71>>
      })

    ref =
      Jason.encode!(%{engine: "anatomy-program", version: 1, title: "Lock", caption: "Test", artifact_id: artifact.id})

    {:ok, page} = Pages.create_page(owner, %{"title" => "Figure", "body" => "```leitor-figure\n#{ref}\n```"})
    {:ok, share} = Sharing.set_link(owner, page.id, %{"link_role" => "view"})
    path = ~p"/s/#{share.token}/figures/#{artifact.id}"
    loaded = conn |> put_req_header("accept", "application/json") |> get(path)
    payload = json_response(loaded, 200)
    assert payload["bundle"] == Base.encode64("program")
    refute Map.has_key?(payload, "source")
    refute Map.has_key?(payload, "report")
    assert get_resp_header(loaded, "cache-control") == ["private, no-store"]
    assert conn |> get(~p"/s/#{share.token}/figures/#{Ecto.UUID.generate()}") |> response(404) == "Not found"
    Sharing.set_link(owner, page.id, %{"link_role" => "disabled"})
    assert conn |> get(path) |> response(404) == "Not found"
    assert conn |> get(~p"/s/invalid/sign-in") |> response(404) == "Not found"
  end
end
