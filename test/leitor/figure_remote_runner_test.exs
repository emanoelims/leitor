defmodule Leitor.FigureRemoteRunnerTest do
  use ExUnit.Case, async: true

  alias Leitor.Figures.RemoteRunner

  defp config do
    [
      url: "http://checker.internal",
      token: "private-test-checker-token-32-bytes",
      poll_interval: 1,
      request_options: [plug: {Req.Test, __MODULE__}]
    ]
  end

  test "private asynchronous checks authenticate both requests and decode bounded evidence" do
    id = Ecto.UUID.generate()

    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer private-test-checker-token-32-bytes"]

      case conn.method do
        "POST" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body) == %{"model.mjs" => "pure model"}
          conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{id: id})

        "GET" ->
          assert conn.request_path == "/checks/#{id}"

          Req.Test.json(conn, %{
            report: %{ok: true, images: ["light.png"]},
            images: [Base.encode64(<<137, 80, 78, 71, 13, 10, 26, 10>>)],
            bundle: "checked bundle",
            style: "svg{}"
          })
      end
    end)

    assert {:ok, result} = RemoteRunner.check(%{"model.mjs" => "pure model"}, config())
    assert result.bundle == "checked bundle"
    assert length(result.images) == 1
  end

  test "failed reports never return executable fields even if the peer includes them" do
    stub_result(%{
      report: %{ok: false, images: [], errors: ["failed constraints"]},
      images: [],
      bundle: "not executable",
      style: "bad"
    })

    assert {:ok, result} = RemoteRunner.check(%{}, config())
    refute Map.has_key?(result, :bundle)
    refute Map.has_key?(result, :style)
  end

  test "model-only evidence returns no executable bundle" do
    stub_result(%{report: %{ok: true, model_only: true, images: []}, images: [], bundle: "not executable"})
    assert {:ok, result} = RemoteRunner.check(%{}, config())
    refute Map.has_key?(result, :bundle)
  end

  test "unexpected filenames, malformed images and incomplete executable responses fail closed" do
    for result <- [
          %{report: %{ok: true, images: ["../secret"]}, images: ["not-base64"]},
          %{report: %{ok: true, images: ["light.png"]}, images: ["not-base64"]},
          %{report: %{ok: true, images: []}, images: [], bundle: "no captures", style: ""}
        ] do
      stub_result(result)
      assert {:error, :invalid_response} = RemoteRunner.check(%{}, config())
    end
  end

  test "redirects and busy peers are not followed or retried" do
    for status <- [302, 429, 503] do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "POST"
        conn |> Plug.Conn.put_resp_header("location", "https://another-host.test/") |> Plug.Conn.send_resp(status, "")
      end)

      assert {:error, :runner_unavailable} = RemoteRunner.check(%{}, config())
    end
  end

  defp stub_result(result) do
    id = Ecto.UUID.generate()

    Req.Test.stub(__MODULE__, fn conn ->
      if conn.method == "POST",
        do: conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{id: id}),
        else: Req.Test.json(conn, result)
    end)
  end
end
