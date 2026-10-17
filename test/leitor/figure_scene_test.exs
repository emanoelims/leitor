defmodule Leitor.FigureSceneTest do
  use ExUnit.Case, async: true

  alias Leitor.Figures
  alias Leitor.Figures.Scene

  @source File.read!("test/fixtures/figures/gears.json")

  test "authored scenes preserve independently specified positions and primitive forms" do
    assert {:ok, scene} = Figures.decode(@source)
    assert scene.engine == "anatomy-scene"
    assert scene.parts |> Enum.map(& &1.kind) |> Enum.uniq() |> length() == 4
    assert Enum.at(scene.parts, 5).position == [42.0, 0.0, 52.0]
    assert {:ok, rebuilt} = scene |> Jason.encode!() |> Figures.decode()
    assert rebuilt == scene
  end

  test "malformed frames, excessive geometry, invalid openings and profiles are rejected" do
    attrs = Jason.decode!(@source)

    for fields <- [
          %{"axis" => [0, 0, 0]},
          %{"axis" => [0, 1]},
          %{"size" => [-1, 2, 3]},
          %{"repeat" => 100},
          %{"kind" => "javascript"},
          %{"kind" => "lathe", "profile" => [[]]},
          %{"kind" => "lathe", "profile" => [[3, 2], [0, 5]]},
          %{"kind" => "ring", "size" => [2, 3, 4]}
        ] do
      bad = Map.update!(attrs, "parts", fn [first | rest] -> [Map.merge(first, fields) | rest] end)
      assert {:error, %Ecto.Changeset{}} = Scene.new(bad)
      assert {:error, :invalid_figure} = Figures.decode(Jason.encode!(bad))
    end

    too_many = Map.update!(attrs, "parts", fn parts -> Enum.map(1..100, fn _ -> Map.put(hd(parts), "repeat", 24) end) end)
    assert {:error, %Ecto.Changeset{}} = Scene.new(too_many)
    assert {:error, %Ecto.Changeset{}} = Scene.new(%{})
  end

  test "the provider schema exposes construction primitives rather than predefined station templates" do
    schema = Scene.schema()
    assert schema.properties.parts.items.properties.kind.enum == ~w(box cylinder ring sphere gear lathe)
    assert Scene.instruction() =~ "NO predefined base"
    refute Map.has_key?(schema.properties, :stages)
  end
end
