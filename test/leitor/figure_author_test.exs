defmodule Leitor.FigureAuthorTest do
  use Leitor.DataCase, async: true

  import Leitor.AccountsFixtures

  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Artifact
  alias Leitor.Figures.Artifacts
  alias Leitor.Figures.Author
  alias Leitor.Figures.Source

  defp state(scope) do
    %{
      adapter: Leitor.FigureAuthorStub,
      model: "configured",
      scope: scope,
      progress: fn _ -> :ok end,
      deadline: System.monotonic_time(:millisecond) + 90_000
    }
  end

  test "module phases share one total budget and preserve their actual source" do
    scope = Scope.for_user(user_fixture())
    assert {:ok, attrs} = Author.write(state(scope), "A lock", max_tokens: 16_000)
    assert {:ok, _} = Source.new(attrs)
    assert attrs["geometry"] == Leitor.FigureProgramStub.proposal()["geometry"]
    assert_receive {:plan_schema, schema}
    assert schema.properties["model"] == %{type: "string"}
    assert schema.properties["experiments"].type == "array"
    refute Map.has_key?(schema.properties["experiments"], :maxItems)
    assert schema.properties["reuse_model"].enum == [false]
    assert schema.properties["experiments"].items.properties.steps.type == "array"
    refute Map.has_key?(schema.properties["experiments"].items.properties.steps.items.properties.value, :minLength)
    assert_receive {:phase, "model", 6400}
    assert_receive {:phase, "geometry", 5600}
    assert_receive {:phase, "figure", 4000}
    refute_receive {:phase, _, _}
  end

  test "a late interruption preserves completed modules and partial source without publishing" do
    scope = Scope.for_user(user_fixture())
    Process.put(:fail_phase, "figure")
    assert {:error, :provider_error} = Author.write(state(scope), "A lock", max_tokens: 16_000)
    revisions = Repo.all(Artifact)
    assert length(revisions) == 3
    assert Enum.all?(revisions, &(&1.status == "draft" and is_nil(&1.bundle)))
    artifact = Enum.find(revisions, &(&1.report["error"] == "provider_interrupted"))
    assert artifact.source["phase"] == "figure"
    assert artifact.source["completed"]["geometry"] == Leitor.FigureProgramStub.proposal()["geometry"]
    assert artifact.source["partial_source"] =~ "mount"
    refute Artifacts.get_ready(scope, artifact.id)
  end

  test "unused reported output is available to the next phase without exceeding the shared total" do
    Process.put(:report_figure_usage, true)
    scope = Scope.for_user(user_fixture())
    assert {:ok, attrs} = Author.write(state(scope), "A lock", max_tokens: 16_000)
    assert_receive {:phase, "model", 6400}
    assert_receive {:phase, "geometry", 10_000}
    assert_receive {:phase, "figure", 13_000}
    assert attrs["__figure_output_tokens"] == 4000
    assert Enum.map(attrs["__figure_usage"], & &1.output_tokens) == [2000, 1000, 1000]
  end

  test "a validated completed model can resume at geometry without another model call" do
    scope = Scope.for_user(user_fixture())
    plan = Map.drop(Leitor.FigureProgramStub.proposal(), ~w(geometry figure))
    resumed = Map.put(state(scope), :resume, %{"completed" => plan, "phase" => "geometry"})
    assert {:ok, _} = Author.write(resumed, "A lock", max_tokens: 16_000)
    assert_receive {:phase, "geometry", 12_000}
    assert_receive {:phase, "figure", 4000}
    refute_receive {:phase, "model", _}
  end

  test "explicit model reuse retains the existing passing experiments" do
    Process.put(:reuse_figure_model, true)
    scope = Scope.for_user(user_fixture())
    baseline = Leitor.FigureProgramStub.proposal()
    refining = Map.put(state(scope), :baseline, baseline)
    assert {:ok, attrs} = Author.write(refining, "Improve the drawing", max_tokens: 16_000)
    assert attrs["model"] == baseline["model"]
    assert attrs["experiments"] == baseline["experiments"]
    assert_receive {:plan_schema, schema}
    refute Map.has_key?(schema.properties["model"], :minLength)
    assert schema.properties["experiments"].minItems == 0
  end

  test "a model cannot reuse an absent baseline or run later phases with empty source" do
    Process.put(:reuse_figure_model, true)
    scope = Scope.for_user(user_fixture())
    assert {:error, :invalid_response} = Author.write(state(scope), "A lock", max_tokens: 16_000)
    assert_receive {:phase, "model", _}
    refute_receive {:phase, "geometry", _}
    assert Repo.one!(Artifact).status == "draft"
  end
end
