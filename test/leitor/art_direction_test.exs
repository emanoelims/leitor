defmodule Leitor.ArtDirectionTest do
  use ExUnit.Case, async: true

  alias Leitor.ArtDirection

  test "shared generation has no extra planning charge; personal plans are bounded and credentials remain request local" do
    assert {:ok, "format"} = ArtDirection.prepare(Leitor.LanguageCapture, "model", "brief", "format", [])
    refute_receive {:language_request, _, _, _}
    Process.put(:language_result, {:ok, %{"direction" => "Fine isometric paths and one moving connector."}})
    options = [api_key: "test-art-direction-private-key", max_tokens: 16_000, total_timeout: 240_000]
    assert {:ok, direction} = ArtDirection.prepare(Leitor.LanguageCapture, "opus", "brief", "format", options)
    assert direction =~ "Fine isometric paths"
    assert_receive {:language_request, "opus", prompt, schema}
    assert schema.required == ["direction"]
    refute prompt =~ "test-art-direction-private-key"
    assert_receive {:language_options, passed}
    assert passed[:max_tokens] == 4096
    assert passed[:api_key] == "test-art-direction-private-key"
    Process.put(:language_result, {:error, :provider_error})
    assert {:error, :provider_error} = ArtDirection.prepare(Leitor.LanguageCapture, "opus", "brief", "format", options)
    Process.put(:language_result, {:ok, %{"direction" => String.duplicate("x", 6001)}})
    assert {:error, :invalid_response} = ArtDirection.prepare(Leitor.LanguageCapture, "opus", "brief", "format", options)
  end
end
