defmodule Leitor.FigureTransportTest do
  use ExUnit.Case, async: true

  alias Leitor.Language.Provider
  alias ReqLLM.Providers.Anthropic

  test "the Anthropic transport retains the authorized output budget for an authored program" do
    owner = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:request_body, Jason.decode!(body)})

      response = %{
        id: "test",
        type: "message",
        role: "assistant",
        model: "claude-opus-5-5",
        content: [%{type: "text", text: ~s({"value":"ok"})}],
        stop_reason: "end_turn",
        usage: %{input_tokens: 10, output_tokens: 10}
      }

      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end

    schema = %{type: "object", additionalProperties: false, required: ["value"], properties: %{value: %{type: "string"}}}

    Provider.generate("anthropic:claude-opus-5-5", "A program", schema,
      max_tokens: 16_000,
      reasoning_effort: :none,
      provider_options: [output_config: %{effort: "low"}],
      api_key: "transport-test-key",
      req_http_options: [plug: plug]
    )

    assert_receive {:request_body, body}
    assert body["max_tokens"] == 16_000
    assert body["output_config"]["effort"] == "low"
    refute Map.has_key?(body, "thinking")
  end

  test "streaming and subscription shaping preserve native low effort" do
    {:ok, model} = ReqLLM.model(%{provider: :anthropic, id: "claude-opus-5-5"})
    context = ReqLLM.context("Write a geometry module")

    for key <- ["transport-test-key", "sk-ant-oat01-transport-test"] do
      assert {:ok, request} =
               Anthropic.attach_stream(
                 model,
                 context,
                 [
                   max_tokens: 24_000,
                   reasoning_effort: :none,
                   provider_options: [output_config: %{effort: "low"}],
                   api_key: key
                 ],
                 nil
               )

      body = Jason.decode!(request.body)
      assert body["max_tokens"] == 24_000
      assert body["output_config"]["effort"] == "low"
      refute Map.has_key?(body, "thinking")
    end
  end
end
