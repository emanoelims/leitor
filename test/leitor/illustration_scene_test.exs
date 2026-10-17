defmodule Leitor.Illustration.SceneTest do
  use ExUnit.Case, async: true

  alias Leitor.Illustration
  alias Leitor.Illustration.Scene
  alias Leitor.Illustration.SVG

  @svg ~s|<svg viewBox="0 0 800 400"><title>Connections</title><defs><linearGradient id="shade"><stop stop-color="#fff"/><stop offset="1" stop-color="#dde"/></linearGradient><clipPath id="window"><rect width="800" height="400"/></clipPath></defs><g clip-path="url(#window)"><g id="plug"><rect x="10" y="10" width="100" height="100" fill="url(#shade)"/></g><path id="signal" d="M0 0L100 100" stroke="#567"/></g></svg>|

  test "gradient references stay local and every render isolates IDs" do
    assert {:ok, svg} = SVG.prepare(@svg)
    assert svg.width == 800
    assert svg.height == 400
    assert svg.markup =~ "url(##{svg.ids["shade"]})"
    assert svg.markup =~ "url(##{svg.ids["window"]})"
    assert {:ok, other} = SVG.prepare(@svg)
    assert svg.ids["plug"] != other.ids["plug"]
    assert {:ok, _} = SVG.prepare(String.replace(@svg, "<title>", "<!-- safe layer note --><title>"))

    for source <- [
          String.replace(@svg, "url(#shade)", "url(https://example.test/paint)"),
          String.replace(@svg, "url(#shade)", ~S|u\72l(https://example.test/paint)|),
          String.replace(@svg, "url(#shade)", "url(#missing)"),
          String.replace(@svg, "id=\"plug\"", "id=\"shade\""),
          String.replace(@svg, "fill=\"url(#shade)\"", "onload=\"alert(1)\"")
        ] do
      assert {:error, :invalid_svg} = SVG.prepare(source)
    end
  end

  test "a preserved Opus illustration renders as artwork while its prose remains source-addressable" do
    markdown = File.read!("test/fixtures/creative/reading_connection.md")
    assert Illustration.valid_visual_markdown?(markdown)
    document = Leitor.PageDocument.prepare(markdown)
    assert length(document.blocks) == 4
    assert document.html =~ "data-scene="
    assert document.html =~ "<linearGradient"
    assert document.text =~ "O conector é a atenção ativa."
    refute document.text =~ "stroke-width"
    refute document.html =~ "Illustration unavailable"
  end

  test "scene motion targets existing layers and stays declarative" do
    attrs = %{
      "svg" => @svg,
      "animations" => [
        %{"target" => "plug", "kind" => "translate", "axis" => "x", "from" => 18, "to" => 0, "duration" => 2800}
      ]
    }

    assert {:ok, scene} = Scene.new(attrs)
    assert {:ok, svg} = SVG.prepare(scene.svg)
    assert [%{target: target, kind: "translate", duration: 2800}] = Scene.animations(scene, svg)
    assert target == svg.ids["plug"]
    json = Jason.encode!(attrs)
    assert {:ok, _} = Scene.from_json(json)
    html = Illustration.render(json, "leitor-scene")
    assert html =~ "data-scene="
    assert html =~ "<svg"
    assert html =~ "data-illustration-toggle"
    refute html =~ "<script"
    assert Illustration.valid_markdown?("```leitor-scene\n#{json}\n```")
    assert Illustration.valid_visual_markdown?("```leitor-scene\n#{json}\n```")
    refute Illustration.valid_visual_markdown?("Only prose without the requested drawing.")

    for change <- [
          %{"target" => "unknown"},
          %{"kind" => "script"},
          %{"duration" => 1},
          %{"kind" => "opacity", "to" => 9000},
          %{"delay" => 100_000}
        ] do
      animation = Map.merge(hd(attrs["animations"]), change)
      assert {:error, _} = Scene.new(%{attrs | "animations" => [animation]})
    end

    for input <- [nil, "[]", "not JSON", String.duplicate("a", 98_305), ~s({"svg":"<script/>"})] do
      assert {:error, :invalid_scene} = Scene.from_json(input)
    end

    assert Illustration.render("{", "leitor-scene", false) =~ "is-drawing"
    assert Illustration.render("{", "leitor-scene") =~ "is-unavailable"
  end
end
