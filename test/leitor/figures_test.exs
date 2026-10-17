defmodule Leitor.FiguresTest do
  use ExUnit.Case, async: true

  alias Leitor.Figures
  alias Leitor.Figures.Flow
  alias Leitor.Figures.Scene

  @source File.read!("test/fixtures/figures/workbench.json")

  test "portable blueprints retain their engine version and reject unknown engines, oversized input and invalid mechanisms" do
    assert {:ok, figure} = Figures.decode(@source)
    assert figure.version == 1
    assert length(figure.stages) == 3
    figure = Jason.decode!(@source)

    for attrs <- [
          Map.put(figure, "engine", "Elixir.System"),
          Map.put(figure, "version", 2),
          Map.put(figure, "stages", []),
          Map.put(figure, "queue_limit", 99),
          Map.put(figure, "arrival_seconds", 0),
          Map.put(figure, "stages", [%{"kind" => "eval", "label" => "Bad", "seconds" => 1}])
        ] do
      assert {:error, :invalid_figure} = Figures.decode(Jason.encode!(attrs))
    end

    for input <- [nil, "[]", "{}", "not json", String.duplicate(" ", 12_001)] do
      assert {:error, :invalid_figure} = Figures.decode(input)
    end

    assert {:error, %Ecto.Changeset{}} = Flow.new(%{})
  end

  test "figure text is escaped and never becomes page markup, and figures do not corrupt prose anchors" do
    source = @source |> Jason.decode!() |> Map.put("title", "<img src=x onerror=alert(1)>") |> Jason.encode!()
    markdown = "Before.\n\n```leitor-figure\n#{source}\n```\n\nAfter."
    assert Leitor.Illustration.valid_visual_markdown?(markdown)
    prepared = Leitor.PageDocument.prepare(markdown)
    assert prepared.text == "Before.\n\nAfter."
    assert prepared.html =~ "data-figure="
    refute prepared.html =~ "<img src=x"
    assert Leitor.WritingDocument.render(markdown) =~ "data-figure="
    refute Leitor.Illustration.valid_visual_markdown?("```leitor-figure\n{}\n```")
  end

  test "generation forwards request-local options, validates completion before emitting, and propagates provider errors" do
    attrs = Jason.decode!(File.read!("test/fixtures/figures/gears.json"))

    Process.put(
      :language_result,
      {:ok, %{"before" => "A small workshop.", "figure" => attrs, "after" => "Pause the second station."}}
    )

    assert {:ok, %{"markdown" => markdown}} =
             Figures.generate(Leitor.LanguageCapture, "opus", "Explain editing", &send(self(), {:delta, &1}),
               api_key: "private-test-key",
               figure_edit: false,
               max_tokens: 2500
             )

    assert markdown =~ "```leitor-figure"
    assert_receive {:delta, ^markdown}
    assert_receive {:language_request, "opus", prompt, schema}
    refute prompt =~ "private-test-key"
    assert schema.properties.figure == Scene.schema()
    assert prompt =~ "NO predefined base"
    assert_receive {:language_options, options}
    assert options[:api_key] == "private-test-key"
    assert options[:max_tokens] == 2500
    refute Keyword.has_key?(options, :figure_edit)

    for result <- [
          {:ok, %{"before" => "x", "figure" => %{}, "after" => "x"}},
          {:ok, %{"markdown" => "No figure"}},
          {:ok, %{"before" => "", "figure" => attrs, "after" => "x"}}
        ] do
      Process.put(:language_result, result)

      assert {:error, :invalid_response} =
               Figures.generate(Leitor.LanguageCapture, "opus", "brief", &send(self(), {:delta, &1}), [])

      refute_receive {:delta, _}
    end

    Process.put(:language_result, {:error, :unavailable})
    assert {:error, :unavailable} = Figures.generate(Leitor.LanguageCapture, "opus", "brief", fn _ -> :ok end, [])
  end

  test "an existing program cannot be silently replaced by a declarative scene without its isolated checker" do
    assert {:error, :runner_unavailable} =
             Figures.generate(Leitor.LanguageCapture, "opus", "Adjust", fn _ -> flunk("Unexpected result") end,
               figure_edit: true
             )

    refute_receive {:language_request, _, _, _}
  end
end
