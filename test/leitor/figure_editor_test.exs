defmodule Leitor.FigureEditorTest do
  use Leitor.DataCase, async: false

  import Leitor.AccountsFixtures

  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Artifact
  alias Leitor.Figures.Editor

  setup do
    old = Application.get_env(:leitor, :figure_runner_adapter)
    Application.put_env(:leitor, :figure_runner_adapter, Leitor.FigureProgramStub)

    on_exit(fn ->
      if old,
        do: Application.put_env(:leitor, :figure_runner_adapter, old),
        else: Application.delete_env(:leitor, :figure_runner_adapter)
    end)

    :ok
  end

  test "native tool turns read, patch, render and finish without rewriting the mechanism" do
    owner = owner()
    baseline = owner.baseline

    assert {:ok, attrs} = Editor.write(owner, "Improve the drawing", max_tokens: 6000)
    assert attrs["geometry"] == "export const shape=2"
    assert attrs["model"] == baseline["model"]
    assert attrs["experiments"] == baseline["experiments"]
    assert attrs["__figure_output_tokens"] == 400
    assert Process.get(:figure_editor_last_options)[:provider_options] == [output_config: %{effort: "medium"}]
  end

  test "a new figure is authored from empty files and cannot finish before a successful render" do
    source = Leitor.FigureProgramStub.proposal()
    Process.put(:figure_editor_script, [{"finish", %{}} | creation_script(source)] ++ [{"render", %{}}, {"finish", %{}}])
    assert {:ok, attrs} = Editor.write(%{owner() | baseline: nil}, "Create an iris from scratch", max_tokens: 6000)
    assert Map.take(attrs, Map.keys(source)) == source
    assert attrs["__figure_output_tokens"] == 900
    assert Enum.all?(Repo.all(Artifact), &(&1.status == "draft" and is_nil(&1.bundle)))
  end

  test "new figures freeze experiment contracts after the first successful render" do
    source = Leitor.FigureProgramStub.proposal()
    metadata = Map.take(source, ~w(title caption before after experiments))
    weakened = Map.put(metadata, "experiments", Enum.map(source["experiments"], &Map.put(&1, "contains", "weakened")))

    Process.put(
      :figure_editor_script,
      creation_script(source) ++
        [{"render", %{}}, {"write_file", %{path: "metadata.json", content: Jason.encode!(weakened)}}, {"render", %{}}]
    )

    assert {:error, :figure_review_failed} =
             Editor.write(%{owner() | baseline: nil}, "Create a mechanism", max_tokens: 6000)
  end

  test "mechanical checks cannot be weakened during a visual repair" do
    Process.put(:figure_editor_script, [
      {"write_file", %{path: "checks.mjs", content: "export function verify(){return []}"}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:error, :figure_review_failed} = Editor.write(owner(), "Repair the supports", max_tokens: 6000)
    refute_receive :isolated_figure_checked
  end

  test "a visual repair can append stronger checks without modifying the existing verifier" do
    baseline = owner()
    original = baseline.baseline["checks"]
    extended = original <> "\nexport function verifyExtra1(){return [{name:'axial contact',passed:2>1}]}"

    Process.put(:figure_editor_script, [
      {"write_file", %{path: "checks.mjs", content: extended}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:ok, attrs} = Editor.write(baseline, "Strengthen 3D contact checks", max_tokens: 6000)
    assert attrs["checks"] == extended
    assert String.starts_with?(attrs["checks"], original)
  end

  test "new native figures require mechanical checks before their first render" do
    source = Leitor.FigureProgramStub.proposal()
    script = Enum.reject(creation_script(source), fn {_name, %{path: path}} -> path == "checks.mjs" end)
    Process.put(:figure_editor_script, script ++ [{"render", %{}}, {"finish", %{}}])

    assert {:error, :figure_review_failed} =
             Editor.write(%{owner() | baseline: nil}, "Create an original mechanism", max_tokens: 6000)

    refute_receive :isolated_figure_checked
    context = Process.get(:figure_editor_last_context)

    assert Enum.any?(context.messages, fn message ->
             message.role == :tool and
               Enum.any?(message.content, &(&1.type == :text and &1.text == "missing_model_checks"))
           end)
  end

  test "a source edit invalidates the successful render before finishing" do
    Process.put(:figure_editor_script, [
      {"render", %{}},
      {"patch_file", %{path: "geometry.mjs", old: "shape=1", new: "shape=2"}},
      {"finish", %{}}
    ])

    assert {:error, :figure_review_failed} = Editor.write(owner(), "Repair the supports", max_tokens: 6000)
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
  end

  test "a fresh successful render survives stage exhaustion without a ceremonial finish call" do
    Process.put(:figure_editor_script, [{"render", %{}}])
    assert {:ok, attrs} = Editor.write(owner(), "Verify the current source", max_tokens: 1000)
    assert attrs["__figure_output_tokens"] == 100
    assert attrs["__figure_verified"].result.report["ok"]
    assert_receive :isolated_figure_checked
    assert Process.get(:figure_editor_stage) == 1
  end

  test "an original construction exhausted between modules returns only private files and accounted usage" do
    Process.put(:figure_editor_script, [{"write_file", %{path: "model.mjs", content: "export const radius=12"}}])

    assert {:incomplete, files, %{output_tokens: 100, usage: [_]}} =
             Editor.write(%{owner() | baseline: nil}, "Create an original mechanism", max_tokens: 1000)

    assert files["model"] == "export const radius=12"
    assert files["figure"] == ""
    refute Map.has_key?(files, "__figure_verified")
    refute_receive :isolated_figure_checked
    assert Enum.all?(Repo.all(Artifact), &(&1.status == "draft" and is_nil(&1.bundle)))
  end

  test "partial construction cannot reset contracts after a successful render" do
    source = Leitor.FigureProgramStub.proposal()
    state = Map.put(%{owner() | baseline: nil}, :resume, source)

    Process.put(:figure_editor_script, [
      {"render", %{}},
      {"write_file", %{path: "geometry.mjs", content: "export const shape=2"}}
    ])

    assert {:incomplete, files, continuation} =
             Editor.write(state, "Continue the original construction", max_tokens: 1100)

    assert continuation.contracts == %{experiments: source["experiments"], checks: source["checks"]}
    refute Map.has_key?(files, "__figure_verified")
    assert_receive :isolated_figure_checked

    resumed = Map.merge(state, %{resume: files, frozen_contracts: continuation.contracts})
    metadata = Map.take(source, ~w(title caption before after experiments))
    weakened = Map.put(metadata, "experiments", Enum.map(source["experiments"], &Map.put(&1, "contains", "weakened")))

    for {path, content} <- [
          {"checks.mjs", "export function verify(){return []}"},
          {"metadata.json", Jason.encode!(weakened)}
        ] do
      Process.put(:figure_editor_stage, 0)

      Process.put(:figure_editor_script, [
        {"write_file", %{path: path, content: content}},
        {"render", %{}},
        {"finish", %{}}
      ])

      assert {:error, :figure_review_failed} = Editor.write(resumed, "Retain frozen contracts", max_tokens: 6000)
    end

    refute_receive :isolated_figure_checked
    refute Enum.any?(Repo.all(Artifact), &(&1.status == "ready"))
  end

  test "an isolated model check cannot satisfy the full render requirement" do
    Process.put(:figure_editor_script, [{"verify_model", %{}}, {"finish", %{}}])
    assert {:error, :figure_review_failed} = Editor.write(owner(), "Verify mechanics before drawing", max_tokens: 6000)
    assert_receive :isolated_figure_checked
    assert Repo.all(Artifact) == []
  end

  test "a truncated turn reduces planning effort until a complete edit without weakening verification" do
    Process.put(:figure_editor_script, [
      {"truncated", %{}},
      {"read_file", %{path: "geometry.mjs"}},
      {"write_file", %{path: "geometry.mjs", content: "export const shape=2"}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:ok, attrs} = Editor.write(owner(), "Repair the supports", max_tokens: 6000)
    efforts = Enum.map(Process.get(:figure_editor_options), & &1[:provider_options][:output_config].effort)
    assert efforts == ["medium", "low", "low", "medium", "medium"]
    assert attrs["geometry"] == "export const shape=2"
    assert attrs["__figure_output_tokens"] == 500
    assert hd(attrs["__figure_usage"]).finish_reason == "length"
    context = Process.get(:figure_editor_last_context)

    assert Enum.any?(context.messages, fn message ->
             message.role == :user and
               Enum.any?(
                 message.content,
                 &(&1.type == :text and String.contains?(&1.text, "Do not repeat the full plan"))
               )
           end)

    assert attrs["__figure_verified"].result.report["ok"]
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
  end

  test "a token-exhausted continuation retains its recovery effort without carrying render evidence" do
    Process.put(:figure_editor_script, [{"truncated", %{}}])
    assert {:incomplete, files, continuation} = Editor.write(owner(), "Continue the next edit", max_tokens: 1000)
    assert continuation.effort == "low"
    refute Map.has_key?(files, "__figure_verified")

    Process.put(:figure_editor_stage, 0)
    Process.put(:figure_editor_options, [])
    Process.put(:figure_editor_script, [{"render", %{}}, {"finish", %{}}])

    state =
      Map.merge(owner(), %{resume: files, author_effort: continuation.effort, frozen_contracts: continuation.contracts})

    assert {:ok, attrs} = Editor.write(state, "Continue the next edit", max_tokens: 6000)
    assert hd(Process.get(:figure_editor_options))[:provider_options][:output_config].effort == "low"
    assert attrs["__figure_verified"].result.report["ok"]
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
  end

  test "legacy contracts without a persisted successful reference are never labeled as unfrozen" do
    Process.put(:figure_editor_script, [{"write_file", %{path: "geometry.mjs", content: "export const shape=2"}}])
    assert {:incomplete, _, continuation} = Editor.write(owner(), "Continue a legacy revision", max_tokens: 1000)
    assert is_list(continuation.contracts.experiments)
    assert is_binary(continuation.contracts.checks)
    assert is_nil(continuation.contract_revision)
    assert Enum.all?(Repo.all(Artifact), &(not Map.has_key?(&1.report, "recovery")))
  end

  test "a truncated tool argument is not saved and receives bounded-edit recovery guidance" do
    Process.put(:figure_editor_script, [
      {"truncated_tool", %{}},
      {"write_file", %{path: "geometry.mjs", content: "export const shape=2"}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:ok, attrs} = Editor.write(owner(), "Recover a cut-off module", max_tokens: 6000)
    assert attrs["geometry"] == "export const shape=2"

    assert Enum.map(Process.get(:figure_editor_options), & &1[:provider_options][:output_config].effort) ==
             ["medium", "low", "medium", "medium"]

    context = Process.get(:figure_editor_last_context)
    text = Jason.encode!(context)
    assert text =~ "Invalid JSON arguments"
    assert text =~ "build a larger module through several exact patches"
    assert_receive :isolated_figure_checked
    assert Enum.all?(Repo.all(Artifact), &(&1.source["geometry"] == "export const shape=2" and &1.status == "draft"))
  end

  test "private coding and render checkpoints retain bounded visual repair history" do
    evidence = [%{visual: %{accept: false, critique: "Keep the far-side pins connected"}}]

    Process.put(:figure_editor_script, [
      {"write_file", %{path: "geometry.mjs", content: "export const shape=2"}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:ok, _attrs} = Editor.write(Map.put(owner(), :evidence, evidence), "Repair the section", max_tokens: 6000)
    artifacts = Repo.all(Artifact)
    assert length(artifacts) == 2

    assert Enum.all?(artifacts, fn artifact ->
             artifact.report["history"] == [
               %{"visual" => %{"accept" => false, "critique" => "Keep the far-side pins connected"}}
             ] and is_nil(artifact.bundle)
           end)
  end

  test "an incomplete original program resumes its saved modules without substituting a template" do
    source = Leitor.FigureProgramStub.proposal()
    resumed = Map.put(%{owner() | baseline: nil}, :resume, %{"model" => source["model"]})
    Process.put(:figure_editor_script, tl(creation_script(source)) ++ [{"render", %{}}, {"finish", %{}}])
    assert {:ok, attrs} = Editor.write(resumed, "Continue the original program", max_tokens: 6000)
    assert attrs["model"] == source["model"]
  end

  test "invalid tool access and ambiguous patches cannot escape the fixed file set" do
    Process.put(:figure_editor_script, [
      {"read_file", %{path: "kit.md"}},
      {"read_file", %{path: "/etc/passwd"}},
      {"patch_file", %{path: "geometry.mjs", old: "missing", new: "replacement"}},
      {"finish", %{}}
    ])

    assert {:error, :figure_review_failed} = Editor.write(owner(), "Verify bounds", max_tokens: 6000)
  end

  test "refinement cannot replace the baseline experiment contracts" do
    metadata = Map.take(owner().baseline, ~w(title caption before after experiments))
    experiments = Enum.map(metadata["experiments"], &Map.put(&1, "contains", "weakened"))
    metadata = Map.put(metadata, "experiments", experiments)

    Process.put(:figure_editor_script, [
      {"write_file", %{path: "metadata.json", content: Jason.encode!(metadata)}},
      {"render", %{}}
    ])

    assert {:error, :figure_review_failed} = Editor.write(owner(), "Preserve tests", max_tokens: 6000)
  end

  test "an expired job or depleted output budget stops before contacting the model" do
    assert {:error, :figure_budget_exceeded} =
             Editor.write(%{owner() | deadline: System.monotonic_time(:millisecond) - 1}, "Expired", max_tokens: 6000)

    assert {:error, :figure_budget_exceeded} = Editor.write(owner(), "Depleted", max_tokens: 500)
  end

  test "the author can inspect the exact shared occlusion helper without reading arbitrary files" do
    Process.put(:figure_editor_script, [
      {"read_file", %{path: "occlusion.mjs"}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:ok, _attrs} = Editor.write(owner(), "Inspect the opaque renderer", max_tokens: 6000)
    context = Process.get(:figure_editor_last_context)

    contents =
      for message <- context.messages,
          message.role == :tool,
          part <- message.content,
          part.type == :text,
          do: part.text

    assert Enum.any?(contents, &String.contains?(&1, "Pure, bounded BSP partitioning"))
    assert Enum.any?(contents, &String.contains?(&1, "export function orderSurfaces"))
  end

  test "the author can inspect the actual mechanical primitives without receiving a whole scene" do
    Process.put(:figure_editor_script, [
      {"read_file", %{path: "mechanics.mjs"}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:ok, _attrs} = Editor.write(owner(), "Build a geared mechanism", max_tokens: 6000)
    context = Process.get(:figure_editor_last_context)

    contents =
      for message <- context.messages,
          message.role == :tool,
          part <- message.content,
          part.type == :text,
          do: part.text

    assert Enum.any?(contents, &String.contains?(&1, "export function spurGear"))
    assert Enum.any?(contents, &String.contains?(&1, "export function externalGearPair"))
    assert Enum.any?(contents, &String.contains?(&1, "export function sliderCrank"))
    refute Enum.any?(contents, &String.contains?(&1, "export function mount"))
  end

  defp owner do
    baseline = Leitor.FigureProgramStub.proposal()

    %{
      adapter: Leitor.FigureEditorStub,
      model: "model",
      baseline: baseline,
      scope: Scope.for_user(user_fixture()),
      progress: fn _ -> :ok end,
      deadline: System.monotonic_time(:millisecond) + 1_200_000
    }
  end

  defp creation_script(source) do
    for {file, content} <- [
          {"model.mjs", source["model"]},
          {"checks.mjs", source["checks"]},
          {"geometry.mjs", source["geometry"]},
          {"figure.mjs", source["figure"]},
          {"style.css", source["css"]},
          {"metadata.json", Jason.encode!(Map.take(source, ~w(title caption before after experiments)))}
        ],
        do: {"write_file", %{path: file, content: content}}
  end
end
