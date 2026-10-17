defmodule Leitor.FigureProgramTest do
  use Leitor.DataCase, async: false

  import Leitor.AccountsFixtures

  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Agent
  alias Leitor.Figures.Artifact
  alias Leitor.Figures.Artifacts
  alias Leitor.Figures.Editor
  alias Leitor.Figures.Program
  alias Leitor.Figures.Runner
  alias Leitor.Figures.Source

  setup do
    previous = Application.get_env(:leitor, :figure_runner_adapter)
    Application.put_env(:leitor, :figure_runner_adapter, Leitor.FigureProgramStub)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:leitor, :figure_runner_adapter, previous),
        else: Application.delete_env(:leitor, :figure_runner_adapter)
    end)

    %{scope: Scope.for_user(user_fixture())}
  end

  test "validated references contain no executable source" do
    attrs = %{engine: "anatomy-program", version: 1, title: "Lock", caption: "Study", artifact_id: Ecto.UUID.generate()}
    assert {:ok, _} = Program.new(attrs)
    assert {:ok, reference} = Leitor.Figures.decode(Jason.encode!(attrs))
    refute Map.has_key?(reference, :source)
    assert Leitor.Illustration.valid_visual_markdown?("```leitor-figure\n#{Jason.encode!(attrs)}\n```")
    assert {:error, _} = Program.new(%{attrs | artifact_id: "bad"})
  end

  test "personal budgets create original files through native tools before independent review", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    script =
      Enum.map(
        [
          {"model.mjs", source["model"]},
          {"checks.mjs", source["checks"]},
          {"geometry.mjs", source["geometry"]},
          {"figure.mjs", source["figure"]},
          {"style.css", source["css"]},
          {"metadata.json", Jason.encode!(Map.take(source, ~w(title caption before after experiments)))}
        ],
        fn {path, content} -> {"write_file", %{path: path, content: content}} end
      )

    Process.put(:figure_editor_script, script ++ [{"render", %{}}, {"finish", %{}}])

    assert {:ok, _} =
             Agent.generate(Leitor.FigureEditorStub, "configured-model", "An original mechanism", scope, fn _ -> :ok end,
               max_tokens: 32_768,
               total_timeout: 1_200_000
             )

    ready = Repo.one!(from a in Artifact, where: a.status == "ready")
    assert Map.take(ready.source, Map.keys(source)) == source
    assert ready.report["visual"]["accept"]
    assert Enum.all?(ready.report["usage"], &(&1["phase"] == "code_tools"))
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
  end

  test "original construction continues across stage exhaustion within the same reservation", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()
    files = ~w(model checks geometry figure css)
    paths = ~w(model.mjs checks.mjs geometry.mjs figure.mjs style.css)
    script = Enum.zip_with(files, paths, fn field, path -> {"write_file", %{path: path, content: source[field]}} end)
    metadata = Jason.encode!(Map.take(source, ~w(title caption before after experiments)))

    Process.put(
      :figure_editor_script,
      script ++ [{"write_file", %{path: "metadata.json", content: metadata}}, {"render", %{}}, {"finish", %{}}]
    )

    Process.put(:figure_editor_output_tokens, %{0 => 6500})

    assert {:ok, _} =
             Agent.generate(Leitor.FigureEditorStub, "configured-model", "An original mechanism", scope, fn _ -> :ok end,
               max_tokens: 12_000,
               total_timeout: 1_200_000
             )

    ready = Repo.one!(from a in Artifact, where: a.status == "ready")
    assert Map.take(ready.source, Map.keys(source)) == source
    assert ready.report["visual"]["accept"]
    assert Enum.sum(Enum.map(ready.report["usage"], & &1["output_tokens"])) == 7200
    assert_receive {:allocation, 1500}
    refute_receive {:allocation, _}
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
  end

  test "bad source sizes and invalid browser actions are rejected" do
    valid = Leitor.FigureProgramStub.proposal()
    assert {:ok, source} = Source.new(valid)
    assert Map.has_key?(Source.files(source), "model.mjs")
    assert Source.files(source)["motion_required"]

    for attrs <- [
          %{valid | "figure" => String.duplicate("x", 60_001)},
          %{valid | "checks" => String.duplicate("x", 20_001)},
          %{valid | "experiments" => []},
          %{valid | "experiments" => [%{"bad" => true}, %{}, %{}]},
          Map.put(
            valid,
            "capture_steps",
            List.duplicate(%{"action" => "click", "selector" => "#turn", "value" => ""}, 9)
          ),
          Map.put(valid, "capture_steps", [%{"action" => "eval", "selector" => "#turn", "value" => ""}])
        ] do
      assert {:error, %Ecto.Changeset{}} = Source.new(attrs)
    end

    assert Source.schema().properties["experiments"].type == "array"
    refute Map.has_key?(Source.schema().properties["experiments"], :maxItems)
    refute Map.has_key?(Source.schema().properties["checks"], :maxLength)
  end

  test "a repair continues after stage exhaustion with frozen checks and fresh execution", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()
    continuation_script(source)

    assert {:ok, _} =
             Agent.generate(Leitor.FigureEditorStub, "configured-model", "An original mechanism", scope, fn _ -> :ok end,
               max_tokens: 12_000,
               total_timeout: 1_200_000
             )

    ready = Repo.one!(from a in Artifact, where: a.status == "ready")
    assert ready.source["geometry"] == "export const shape=2"
    assert ready.source["checks"] == source["checks"]
    assert ready.source["experiments"] == source["experiments"]
    assert Enum.sum(Enum.map(ready.report["usage"], & &1["output_tokens"])) == 6900
    assert_receive :isolated_figure_checked
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
    assert_receive {:allocation, 1500}
    refute_receive {:allocation, _}
  end

  test "exhausting the last coding stage reports a budget limit rather than a visual rejection", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    Process.put(:figure_editor_script, [
      {"write_file", %{path: "model.mjs", content: source["model"]}},
      {"write_file", %{path: "checks.mjs", content: source["checks"]}}
    ])

    Process.put(:figure_editor_output_tokens, %{0 => 6100, 1 => 3500})

    assert {:error, :figure_budget_exceeded} =
             Agent.generate(Leitor.FigureEditorStub, "configured-model", "An original mechanism", scope, fn _ -> :ok end,
               max_tokens: 12_000,
               total_timeout: 1_200_000
             )

    refute_receive :isolated_figure_checked
    refute_receive {:allocation, _}
    refute Repo.exists?(from a in Artifact, where: a.status == "ready")
  end

  test "continuation after a passing render cannot weaken its mechanical checks", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()
    continuation_script(source, [{"write_file", %{path: "checks.mjs", content: "export function verify(){return []}"}}])

    assert {:error, :figure_review_failed} =
             Agent.generate(Leitor.FigureEditorStub, "configured-model", "An original mechanism", scope, fn _ -> :ok end,
               max_tokens: 12_000,
               total_timeout: 1_200_000
             )

    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
    refute_receive {:allocation, _}
    refute Repo.exists?(from a in Artifact, where: a.status == "ready")
  end

  defp continuation_script(source, extra \\ []) do
    script =
      Enum.map(
        [
          {"model.mjs", source["model"]},
          {"checks.mjs", source["checks"]},
          {"geometry.mjs", source["geometry"]},
          {"figure.mjs", source["figure"]},
          {"style.css", source["css"]},
          {"metadata.json", Jason.encode!(Map.take(source, ~w(title caption before after experiments)))}
        ],
        fn {path, content} -> {"write_file", %{path: path, content: content}} end
      )

    Process.put(:figure_editor_output_tokens, %{7 => 6000})

    Process.put(
      :figure_editor_script,
      script ++
        [{"render", %{}}, {"write_file", %{path: "geometry.mjs", content: "export const shape=2"}}] ++
        extra ++ [{"render", %{}}, {"finish", %{}}]
    )
  end

  test "reviewed programs are private, immutable and published only after checks", %{scope: scope} do
    assert {:ok, %{"markdown" => markdown}} =
             Agent.generate(
               Leitor.FigureProgramStub,
               "configured-model",
               "A lock",
               scope,
               fn text -> send(self(), {:published, text}) end,
               max_tokens: 6000,
               total_timeout: 90_000,
               figure_checkpoint: fn id -> send(self(), {:checkpoint, id}) end
             )

    assert_receive {:published, ^markdown}
    artifact = Repo.one!(Artifact)
    assert Artifacts.get_ready(scope, artifact.id).bundle == "(()=>{})();"
    assert Artifacts.get_ready(Scope.for_user(user_fixture()), artifact.id) == nil
    assert Artifacts.get_ready(scope, "invalid") == nil
    assert artifact.report["visual"]["accept"]
    assert_receive {:allocation, 4500}
    assert_receive {:allocation, 1500}
    refute_receive {:allocation, _}
    refute_receive {:checkpoint, _}
  end

  test "failed visual review keeps a non-executable draft and respects the budget", %{scope: scope} do
    Process.put(:accept_figure, false)

    assert {:error, :figure_review_failed} =
             Agent.generate(Leitor.FigureProgramStub, "model", "lock", scope, fn _ -> flunk("Draft published") end,
               max_tokens: 6000,
               total_timeout: 90_000,
               figure_checkpoint: fn id -> send(self(), {:checkpoint, id}) end
             )

    artifact = Repo.one!(Artifact)
    assert artifact.status == "draft"
    assert artifact.bundle == nil
    assert Artifacts.get_ready(scope, artifact.id) == nil
    assert_receive {:checkpoint, id}
    assert id == artifact.id
  end

  test "an explicit adjustment authors an approved revision before reviewing it again", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    {:ok, original} =
      Artifacts.store(scope, %{
        title: source["title"],
        caption: source["caption"],
        model: "model",
        source: source,
        status: "ready",
        bundle: "original checked bundle",
        style: "svg{}",
        preview: "png",
        report: %{execution: %{ok: true}, visual: %{accept: true}}
      })

    result =
      Agent.generate(Leitor.FigureEditorStub, "model", "Adjust the figure", scope, fn _ -> :ok end,
        figure_revision: original.id,
        figure_edit: true,
        max_tokens: 32_768,
        total_timeout: 1_200_000
      )

    assert match?({:ok, _}, result), inspect(Enum.map(Repo.all(Artifact), & &1.report))
    revised = Repo.one!(from a in Artifact, where: a.status == "ready" and a.id != ^original.id)
    assert revised.source["geometry"] == "export const shape=2"
    assert revised.source["checks"] == source["checks"]
    assert revised.source["experiments"] == source["experiments"]
    assert Artifacts.get_ready(scope, original.id).bundle == "original checked bundle"
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
    assert_receive {:allocation, 1500}
    refute_receive {:allocation, _}
  end

  test "an expired authorization does not contact the provider", %{scope: scope} do
    assert {:error, :figure_budget_exceeded} =
             Agent.generate(Leitor.FigureProgramStub, "model", "lock", scope, fn _ -> :ok end,
               max_tokens: 6000,
               total_timeout: 0
             )

    refute_receive {:allocation, _}
  end

  test "disabled isolation refuses execution rather than falling back to the host" do
    previous = Application.get_env(:leitor, :figure_runner)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:leitor, :figure_runner, previous),
        else: Application.delete_env(:leitor, :figure_runner)
    end)

    for config <- [nil, [], [enabled: false]] do
      Application.put_env(:leitor, :figure_runner, config)
      assert {:error, :runner_unavailable} = Runner.check(%{})
    end

    Application.delete_env(:leitor, :figure_runner)
    assert {:error, :runner_unavailable} = Runner.check(%{})
  end

  test "repairing a rejected proposal shares the total authorized token budget", %{scope: scope} do
    Process.put(:accept_figure, [false, true])

    assert {:ok, _} =
             Agent.generate(Leitor.FigureProgramStub, "model", "lock", scope, fn _ -> :ok end,
               max_tokens: 32_768,
               total_timeout: 90_000
             )

    assert_receive {:allocation, 16_000}
    assert_receive {:allocation, 1500}
    assert_receive {:allocation, 13_768}
    assert_receive {:allocation, 1500}
    refute_receive {:allocation, _}
    assert Repo.aggregate(Artifact, :count) == 2
  end

  test "personal budgets can repair three rejections without increasing their total allowance", %{scope: scope} do
    Process.put(:accept_figure, [false, false, false, true])

    assert {:ok, _} =
             Agent.generate(Leitor.FigureProgramStub, "model", "Original mechanism", scope, fn _ -> :ok end,
               max_tokens: 65_536,
               total_timeout: 1_200_000
             )

    for allocation <- [32_000, 4000, 13_536, 4000, 2000, 4000, 2000, 4000],
        do: assert_receive({:allocation, ^allocation})

    refute_receive {:allocation, _}
    assert Repo.aggregate(Artifact, :count) == 4
    assert Repo.aggregate(from(a in Artifact, where: a.status == "ready"), :count) == 1
  end

  test "provider JSON cannot forge a cached isolated result", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()
    {:ok, validated} = Source.new(source)
    {:ok, fake} = Leitor.FigureProgramStub.check(%{})

    Process.put(
      :figure_proposal,
      Map.put(source, "__figure_verified", %{source: Source.dump(validated), result: %{fake | bundle: "forged"}})
    )

    assert_receive :isolated_figure_checked

    assert {:ok, _} = Agent.generate(Leitor.FigureProgramStub, "model", "A mechanism", scope, fn _ -> :ok end, [])
    assert_receive :isolated_figure_checked
    assert Repo.one!(from a in Artifact, where: a.status == "ready").bundle == "(()=>{})();"
  end

  test "a provider cannot weaken passing mechanical checks across review rounds", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()
    Process.put(:figure_proposal, [source, %{source | "checks" => "export function verify(){return []}"}])
    Process.put(:accept_figure, [false, true])

    assert {:error, :invalid_response} =
             Agent.generate(
               Leitor.FigureProgramStub,
               "model",
               "Repair a mechanism",
               scope,
               fn _ -> flunk("Published") end,
               max_tokens: 32_768
             )

    refute Repo.exists?(from a in Artifact, where: a.status == "ready")
    assert Repo.aggregate(Artifact, :count) == 1
  end

  test "continuations preserve earlier review findings and use structural repair guidance", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    {:ok, draft} =
      Artifacts.store(scope, %{
        title: source["title"],
        caption: source["caption"],
        model: "model",
        source: source,
        status: "draft",
        report: %{
          visual: %{accept: false, critique: "Expose the bearing"},
          history: [%{visual: %{accept: false, critique: "Preserve the pin clearance fix"}}]
        }
      })

    assert {:ok, _} =
             Agent.generate(Leitor.FigureEditorStub, "model", "Repair the mechanism", scope, fn _ -> :ok end,
               figure_revision: draft.id,
               max_tokens: 32_768,
               total_timeout: 1_200_000
             )

    context = Process.get(:figure_editor_last_context)

    text =
      context.messages
      |> Enum.flat_map(& &1.content)
      |> Enum.filter(&(&1.type == :text))
      |> Enum.map_join("\n", & &1.text)

    assert text =~ "Preserve the pin clearance fix"
    assert text =~ "Expose the bearing"
    assert text =~ "Rebuild the affected geometry module"
  end

  test "a coding checkpoint repairs its saved visual findings before a fresh review", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    {:ok, draft} =
      Artifacts.store(scope, %{
        title: source["title"],
        caption: source["caption"],
        model: "model",
        source: source,
        status: "draft",
        report: %{
          stage: "coding",
          history: [%{visual: %{accept: false, critique: "Reconnect the cutaway bearing"}}]
        }
      })

    assert {:ok, _} =
             Agent.generate(Leitor.FigureEditorStub, "model", "Continue the jack", scope, fn _ -> :ok end,
               figure_revision: draft.id,
               max_tokens: 32_768,
               total_timeout: 1_200_000
             )

    assert Jason.encode!(Process.get(:figure_editor_last_context)) =~ "Reconnect the cutaway bearing"
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
    artifact = Repo.one!(from a in Artifact, where: a.status == "ready")
    assert artifact.source["geometry"] == "export const shape=2"
  end

  test "a later job restores approved contracts even when its latest module is incomplete", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()
    state = editor_state(scope, source)
    Process.put(:figure_editor_script, [{"render", %{}}, {"write_file", %{path: "figure.mjs", content: ""}}])

    assert {:incomplete, _, continuation} = Editor.write(state, "Continue the mechanism", max_tokens: 1100)
    assert is_binary(continuation.contract_revision)
    assert_receive :isolated_figure_checked

    draft = Artifact |> Repo.all() |> Enum.find(&(&1.report["stage"] == "coding"))
    assert draft.source["figure"] == ""
    assert draft.report["recovery"]["contracts_revision"] == continuation.contract_revision

    metadata = Map.take(source, ~w(title caption before after experiments))
    weakened = Map.put(metadata, "experiments", Enum.map(source["experiments"], &Map.put(&1, "contains", "weakened")))
    Process.put(:figure_editor_stage, 0)

    Process.put(:figure_editor_script, [
      {"write_file", %{path: "checks.mjs", content: "export function verify(){return []}"}},
      {"render", %{}},
      {"write_file", %{path: "metadata.json", content: Jason.encode!(weakened)}},
      {"render", %{}},
      {"write_file", %{path: "metadata.json", content: Jason.encode!(metadata)}},
      {"write_file", %{path: "checks.mjs", content: source["checks"]}},
      {"write_file", %{path: "figure.mjs", content: source["figure"]}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:ok, _} =
             Agent.generate(Leitor.FigureEditorStub, "model", "Continue the mechanism", scope, fn _ -> :ok end,
               figure_revision: draft.id,
               max_tokens: 32_768,
               total_timeout: 1_200_000
             )

    artifact = Repo.one!(from a in Artifact, where: a.status == "ready")
    assert artifact.source["checks"] == source["checks"]
    assert artifact.source["experiments"] == source["experiments"]
    text = Jason.encode!(Process.get(:figure_editor_last_context))
    assert text =~ "frozen_model_checks"
    assert text =~ "frozen_experiments"
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
  end

  test "a new job retains low recovery effort and may correct assertions that never passed", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()
    Process.put(:figure_editor_script, [{"truncated", %{}}])
    assert {:incomplete, _, _} = Editor.write(editor_state(scope, source), "Continue", max_tokens: 1000)
    draft = Repo.one!(Artifact)
    assert draft.report["recovery"] == %{"version" => 1, "contracts_revision" => nil, "effort" => "low"}
    Process.put(:figure_editor_stage, 0)
    Process.put(:figure_editor_options, [])
    revised = source["checks"] <> "\n// corrected before first passing render"

    Process.put(:figure_editor_script, [
      {"write_file", %{path: "checks.mjs", content: revised}},
      {"render", %{}},
      {"finish", %{}}
    ])

    assert {:ok, _} =
             Agent.generate(Leitor.FigureEditorStub, "model", "Continue", scope, fn _ -> :ok end,
               figure_revision: draft.id,
               max_tokens: 32_768,
               total_timeout: 1_200_000
             )

    assert hd(Process.get(:figure_editor_options))[:provider_options][:output_config].effort == "low"
    artifact = Repo.one!(from a in Artifact, where: a.status == "ready")
    assert artifact.source["checks"] == revised
    assert_receive :isolated_figure_checked
    refute_receive :isolated_figure_checked
  end

  test "checkpoint contract references must belong to this account and have passed execution", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()
    foreign_scope = Scope.for_user(user_fixture())
    attrs = %{title: "Draft", caption: "Private", model: "model", source: source, status: "draft"}
    {:ok, foreign} = Artifacts.store(foreign_scope, Map.put(attrs, :report, %{execution: %{ok: true}}))
    {:ok, failed} = Artifacts.store(scope, Map.put(attrs, :report, %{execution: %{ok: false}}))

    {:ok, incomplete} =
      Artifacts.store(
        scope,
        attrs |> Map.put(:source, %{"model" => "partial"}) |> Map.put(:report, %{execution: %{ok: true}})
      )

    for reference <- [foreign.id, failed.id, incomplete.id, Ecto.UUID.generate(), "malformed"] do
      {:ok, draft} =
        Artifacts.store(
          scope,
          Map.put(attrs, :report, %{
            stage: "coding",
            recovery: %{version: 1, contracts_revision: reference, effort: "medium"}
          })
        )

      assert {:error, :invalid_response} =
               Agent.generate(Leitor.FigureEditorStub, "model", "Continue", scope, fn _ -> flunk("Published") end,
                 figure_revision: draft.id,
                 max_tokens: 32_768
               )
    end

    refute_receive :isolated_figure_checked
    refute Process.get(:figure_editor_last_context)
    refute Repo.exists?(from a in Artifact, where: a.status == "ready")
  end

  test "malformed recovery metadata cannot downgrade into an unprotected legacy continuation", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    for recovery <- [nil, %{}, %{"version" => 2}, %{"version" => 1, "contracts_revision" => nil, "effort" => "ultra"}] do
      {:ok, draft} =
        Artifacts.store(scope, %{
          title: "Private",
          caption: "Incomplete",
          model: "model",
          source: source,
          status: "draft",
          report: %{stage: "coding", recovery: recovery}
        })

      assert {:error, :invalid_response} =
               Agent.generate(Leitor.FigureEditorStub, "model", "Continue", scope, fn _ -> flunk("Published") end,
                 figure_revision: draft.id,
                 max_tokens: 32_768
               )
    end

    refute_receive :isolated_figure_checked
    refute Process.get(:figure_editor_last_context)
  end

  defp editor_state(scope, source) do
    %{
      adapter: Leitor.FigureEditorStub,
      model: "model",
      scope: scope,
      baseline: nil,
      resume: source,
      progress: fn _ -> :ok end,
      deadline: System.monotonic_time(:millisecond) + 1_200_000
    }
  end

  test "interrupted streaming preserves a private non-executable source draft", %{scope: scope} do
    assert {:error, :provider_error} =
             Agent.generate(
               Leitor.FigureProgramStreamStub,
               "model",
               "lock",
               scope,
               fn _ -> flunk("Partial code published") end,
               max_tokens: 6000,
               total_timeout: 90_000
             )

    artifact = Repo.one!(Artifact)
    assert artifact.source["partial_json"] == "{\"figure\":\"unfinished"
    assert artifact.status == "draft"
    assert artifact.bundle == nil
    refute Artifacts.get_ready(scope, artifact.id)
    assert Artifacts.get_revision(scope, artifact.id).id == artifact.id
  end

  test "continuation cannot load another account's source", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    {:ok, foreign} =
      Artifacts.store(Scope.for_user(user_fixture()), %{
        title: source["title"],
        caption: source["caption"],
        model: "model",
        source: source,
        report: %{},
        status: "draft"
      })

    assert {:error, :invalid_response} =
             Agent.generate(Leitor.FigureProgramStub, "model", "lock", scope, fn _ -> :ok end,
               figure_revision: foreign.id,
               max_tokens: 6000
             )

    assert {:error, :invalid_response} =
             Agent.generate(Leitor.FigureProgramStub, "model", "lock", scope, fn _ -> :ok end,
               figure_revision: Ecto.UUID.generate(),
               max_tokens: 6000
             )

    refute_receive {:allocation, _}
  end

  test "review-only revisions get fresh checks and cannot author or publish a rejected source", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    {:ok, draft} =
      Artifacts.store(scope, %{
        title: source["title"],
        caption: source["caption"],
        model: "model",
        source: source,
        report: %{visual: %{accept: false}},
        status: "draft"
      })

    Process.put(:accept_figure, false)

    assert {:error, :figure_review_failed} =
             Agent.generate(
               Leitor.FigureEditorStub,
               "model",
               "Review supplied source",
               scope,
               fn _ -> flunk("Rejected published") end,
               max_tokens: 32_768,
               total_timeout: 90_000,
               figure_revision: draft.id,
               figure_review_only: true
             )

    assert_receive {:allocation, 1500}
    refute_receive {:allocation, _}
    refute Process.get(:figure_editor_stage)
    refute Repo.exists?(from a in Artifact, where: a.status == "ready")
    assert Repo.aggregate(Artifact, :count) == 2
  end

  test "review-only acceptance still requires the independent gate and preserves supplied source", %{scope: scope} do
    source = Leitor.FigureProgramStub.proposal()

    {:ok, draft} =
      Artifacts.store(scope, %{
        title: source["title"],
        caption: source["caption"],
        model: "model",
        source: source,
        report: %{},
        status: "draft"
      })

    assert {:ok, _markdown} =
             Agent.generate(Leitor.FigureEditorStub, "model", "Review supplied source", scope, fn _ -> :ok end,
               max_tokens: 32_768,
               total_timeout: 90_000,
               figure_revision: draft.id,
               figure_review_only: true
             )

    assert_receive {:allocation, 1500}
    refute_receive {:allocation, _}
    refute Process.get(:figure_editor_stage)
    assert Repo.one!(from a in Artifact, where: a.status == "ready").source == Map.put(source, "capture_steps", [])
  end
end
