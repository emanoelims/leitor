defmodule Leitor.FigureRunnerTest do
  use ExUnit.Case, async: false

  alias Leitor.Figures.Runner
  alias Leitor.Figures.Source

  @moduletag timeout: 120_000
  @moduletag skip: System.get_env("LEITOR_RUN_SANDBOX_TESTS") != "1"
  setup do
    previous = Application.get_env(:leitor, :figure_runner)
    Application.put_env(:leitor, :figure_runner, enabled: true, image: "leitor-figure-runner:1")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:leitor, :figure_runner, previous),
        else: Application.delete_env(:leitor, :figure_runner)
    end)

    :ok
  end

  defp program do
    %{
      "figure.mjs" =>
        ~s|export function mount(root){root.innerHTML='<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="30" fill="#b28b43"/></svg><button id="turn">Turn</button><output id="state">Blocked</output>';root.querySelector('#turn').addEventListener('click',()=>{root.querySelector('#state').textContent='Open';root.querySelector('circle').setAttribute('fill','#579a85')});return ()=>root.replaceChildren()}|,
      "model.mjs" => "export const initial=()=>({angle:0})",
      "geometry.mjs" => "export const radius=30",
      "css" => "svg{width:100%;max-height:300px}button{padding:12px}",
      "experiments" => [
        %{
          "name" => "turn",
          "steps" => [%{"action" => "click", "selector" => "#turn", "value" => ""}],
          "selector" => "#state",
          "contains" => "Open"
        }
      ]
    }
  end

  test "the real networkless container compiles custom code and tests browser interaction" do
    assert {:ok, result} = Runner.check(program())
    assert result.report["ok"], inspect(result.report)
    assert length(result.images) == 4
    assert result.report["network"] == []
    assert result.report["checks"] == [%{"name" => "turn", "passed" => true}]
    assert byte_size(result.bundle) > 500
  end

  for name <- ~w(cardan cam governor ratchet refraction lunar) do
    @tag fixture: name
    test "the original quality campaign #{name} retains its model, controls, motion and mobile framing", %{fixture: name} do
      attrs = "test/fixtures/figures/#{name}-program.json" |> File.read!() |> Jason.decode!()
      {:ok, source} = Source.new(attrs)
      assert {:ok, result} = Runner.check(Source.files(source))
      assert result.report["ok"], inspect(result.report)
      assert length(result.report["model_checks"]) >= 14
      assert Enum.all?(result.report["model_checks"], & &1["passed"])
      assert length(result.report["checks"]) >= 5
      assert result.report["animation_observed"]
      assert result.report["reduced_motion_stable"]
      assert result.report["mobile_framing"]["clipped"] == false
      assert result.report["network"] == []
      assert result.report["errors"] == []
    end
  end

  test "unstyled labels inherit the shared reader/checker foreground in both themes" do
    code =
      ~s|export function mount(root){root.innerHTML='<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="30"/></svg><label id="label">A readable label</label><button id="turn">Dark theme</button><output id="state"></output>';const out=root.querySelector('#state');out.textContent=getComputedStyle(root).color;root.querySelector('#turn').onclick=()=>{document.documentElement.dataset.theme='dark';out.textContent=getComputedStyle(root.querySelector('#label')).color;root.querySelector('circle').setAttribute('fill',out.textContent)};return ()=>root.replaceChildren()}|

    files = %{
      program()
      | "figure.mjs" => code,
        "experiments" => [
          %{
            "name" => "readable dark labels",
            "steps" => [%{"action" => "click", "selector" => "#turn", "value" => ""}],
            "selector" => "#state",
            "contains" => "233, 227, 214"
          }
        ]
    }

    assert {:ok, result} = Runner.check(files)
    assert result.report["ok"], inspect(result.report)
  end

  test "the reviewed lock retains six mechanical outcomes, animation and accessible mobile captures" do
    attrs = "test/fixtures/figures/lock-program.json" |> File.read!() |> Jason.decode!()
    assert {:ok, source} = Source.new(attrs)
    assert {:ok, result} = Runner.check(Source.files(source))
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["checks"]) == 6
    assert Enum.all?(result.report["checks"], & &1["passed"])
    assert result.report["drawing_changes"] >= 4
    assert result.report["animation_observed"]
    assert result.report["reduced_motion_stable"]
    assert result.report["errors"] == []
    assert result.report["network"] == []
    assert length(result.images) == 5
    assert "detail.png" in result.report["images"]
  end

  test "forbidden programs remain non-executable and report the reason" do
    assert {:ok, result} =
             Runner.check(%{program() | "figure.mjs" => "export function mount(root){fetch('https://example.com')}"})

    refute result.report["ok"]
    assert Enum.any?(result.report["errors"], &String.contains?(&1, "fetch"))
    refute Map.has_key?(result, :bundle)
  end

  test "required playback rejects a drawing that only changes after direct button clicks" do
    assert {:ok, result} = Runner.check(Map.put(program(), "motion_required", true))
    refute result.report["ok"]
    refute result.report["animation_observed"]

    assert Enum.any?(
             result.report["errors"],
             &String.contains?(&1, "Playback did not produce time-dependent drawing motion")
           )

    refute Map.has_key?(result, :bundle)
  end

  test "the jack must animate its mechanism as well as preserve sampled constraints and controls" do
    attrs = "test/fixtures/figures/jack-program.json" |> File.read!() |> Jason.decode!()
    assert {:ok, source} = Source.new(attrs)
    assert {:ok, result} = Runner.check(Source.files(source))
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["model_checks"]) >= 17
    assert Enum.all?(result.report["model_checks"], & &1["passed"])
    assert length(result.report["checks"]) >= 5
    assert result.report["animation_observed"]
    assert result.report["reduced_motion_stable"]
    assert result.report["errors"] == []
    assert result.report["network"] == []
  end

  test "mechanical checks execute before mount and a failed constraint prevents publication" do
    checks =
      "export function verify(){return [{name:'pin closure',passed:false,detail:'gap=2 mm'},{name:'dwell',passed:false,detail:'drift=3 degrees'},{name:'bounded pose',passed:true}]}"

    files = program() |> Map.put("checks.mjs", checks) |> Map.put("model_checks_required", true)
    assert {:ok, result} = Runner.check(files)
    refute result.report["ok"]
    assert Enum.any?(result.report["errors"], &String.contains?(&1, "pin closure"))
    assert Enum.count(result.report["model_checks"], &(not &1["passed"])) == 2
    assert Enum.any?(result.report["model_checks"], &(&1["detail"] == "drift=3 degrees"))
    refute Map.has_key?(result, :bundle)
  end

  test "named sampled constraints are recorded independently of UI assertions" do
    checks =
      "import {initial} from './model.mjs';export function verify(){const s=initial();return [{name:'initial angle',passed:s.angle===0},{name:'finite pose',passed:Number.isFinite(s.angle)},{name:'bounded initial travel',passed:Math.abs(s.angle)<=Math.PI}]}"

    files = program() |> Map.put("checks.mjs", checks) |> Map.put("model_checks_required", true)
    assert {:ok, result} = Runner.check(files)
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["model_checks"]) == 3
    assert Enum.all?(result.report["model_checks"], & &1["passed"])

    extended =
      checks <>
        "\nexport function verifyExtra1(){return [{name:'additional axial check',passed:false,detail:'no axial overlap'}]}"

    assert {:ok, rejected} = Runner.check(Map.put(files, "checks.mjs", extended))
    refute rejected.report["ok"]
    assert Enum.count(rejected.report["model_checks"], & &1["passed"]) == 3
    assert Enum.any?(rejected.report["model_checks"], &(&1["name"] == "additional axial check" and not &1["passed"]))
  end

  test "model-only checks need no drawing and return no executable evidence" do
    files =
      program()
      |> Map.put("figure.mjs", "export function mount(){return ()=>{}}")
      |> Map.put(
        "checks.mjs",
        "export function verify(){return [1,2,3].map(n=>({name:'sample '+n,passed:Number.isFinite(n)}))}"
      )
      |> Map.put("experiments", [])
      |> Map.put("model_only", true)
      |> Map.put("model_checks_required", true)

    assert {:ok, result} = Runner.check(files)
    assert result.report["ok"]
    assert result.report["model_only"]
    assert length(result.report["model_checks"]) == 3
    assert result.images == []
    refute Map.has_key?(result, :bundle)
    refute Map.has_key?(result, :style)
  end

  test "the original iris preserves rigid geometry, aperture math, real controls and distinct capture poses" do
    attrs = "test/fixtures/figures/iris-program.json" |> File.read!() |> Jason.decode!()
    assert {:ok, source} = Source.new(attrs)
    invariants = File.read!("test/fixtures/figures/iris-invariants.mjs")
    files = source |> Source.files() |> Map.update!("figure.mjs", &(invariants <> "\n" <> &1))
    assert {:ok, result} = Runner.check(files)
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["checks"]) == 6
    assert Enum.all?(result.report["checks"], & &1["passed"])
    assert result.report["capture_steps"] == 3
    assert Enum.find(result.report["tested_state"]["toggles"], &(&1["id"] == "dia-inspect"))["pressed"] == "true"
    assert Enum.find(result.report["capture_state"]["toggles"], &(&1["id"] == "dia-inspect"))["pressed"] == "false"
    assert result.report["drawing_changes"] >= 4
    assert result.report["animation_observed"]
    assert result.report["reduced_motion_stable"]
    assert result.report["errors"] == []
    assert result.report["network"] == []
    assert length(result.images) == 6
  end

  test "capture actions run after immutable experiments and fail closed when they cannot execute" do
    files = Map.put(program(), "capture_steps", [%{"action" => "click", "selector" => "#missing", "value" => ""}])
    assert {:ok, result} = Runner.check(files)
    refute result.report["ok"]
    assert result.report["checks"] == [%{"name" => "turn", "passed" => true}]
    assert Enum.any?(result.report["errors"], &String.contains?(&1, "#missing"))
    refute Map.has_key?(result, :bundle)
  end

  test "a second original mechanism preserves rigid linkage closure throughout a complete revolution" do
    attrs = "test/fixtures/figures/crank-program.json" |> File.read!() |> Jason.decode!()
    assert {:ok, source} = Source.new(attrs)
    invariants = File.read!("test/fixtures/figures/crank-invariants.mjs")
    files = source |> Source.files() |> Map.update!("figure.mjs", &(invariants <> "\n" <> &1))
    assert {:ok, result} = Runner.check(files)
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["checks"]) == 6
    assert result.report["animation_observed"]
    assert result.report["reduced_motion_stable"]
    assert result.report["errors"] == []
    assert result.report["network"] == []
    assert length(result.images) == 6
  end

  test "shared involute gears and slider-crank primitives drive a real isolated interactive assembly" do
    attrs = "test/fixtures/figures/mechanics-program.json" |> File.read!() |> Jason.decode!()
    assert {:ok, source} = Source.new(attrs)
    invariants = File.read!("test/fixtures/figures/mechanics-invariants.mjs")
    files = source |> Source.files() |> Map.update!("figure.mjs", &(invariants <> "\n" <> &1))
    assert {:ok, result} = Runner.check(files)
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["checks"]) == 6
    assert result.report["animation_observed"]
    assert result.report["reduced_motion_stable"]
    assert result.report["drawing_changes"] >= 4
    assert result.report["errors"] == []
    assert result.report["network"] == []
    assert length(result.images) == 6
    refute String.contains?(result.bundle, "/leitor/mechanics.mjs")
  end

  test "the automatically authored Geneva mechanism preserves contact, dwell, indexing and real interaction" do
    attrs = "test/fixtures/figures/geneva-program.json" |> File.read!() |> Jason.decode!()
    assert {:ok, source} = Source.new(attrs)
    assert {:ok, result} = Runner.check(Source.files(source))
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["model_checks"]) >= 17
    assert Enum.all?(result.report["model_checks"], & &1["passed"])
    assert length(result.report["checks"]) == 6
    assert Enum.all?(result.report["checks"], & &1["passed"])
    assert result.report["animation_observed"]
    assert result.report["reduced_motion_stable"]
    assert result.report["drawing_changes"] >= 4
    assert result.report["errors"] == []
    assert result.report["network"] == []
    assert length(result.images) == 6
  end

  test "the steam mill keeps the piston inside the bore and material clear of both working nips" do
    attrs = "test/fixtures/figures/steam-program.json" |> File.read!() |> Jason.decode!()
    assert {:ok, source} = Source.new(attrs)
    invariants = File.read!("test/fixtures/figures/steam-invariants.mjs")
    files = source |> Source.files() |> Map.update!("figure.mjs", &(invariants <> "\n" <> &1))
    assert {:ok, result} = Runner.check(files)
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["checks"]) == 6
    assert Enum.all?(result.report["checks"], & &1["passed"])
    toggles = Map.new(result.report["tested_state"]["toggles"], &{&1["id"], &1["pressed"]})
    assert toggles["mill-view"] == "true"
    assert toggles["whole-view"] == "false"
    assert result.report["animation_observed"]
    assert result.report["reduced_motion_stable"]
    assert result.report["errors"] == []
    assert result.report["network"] == []
    assert length(result.images) == 6
  end

  test "the automatically authored rack and pinion preserves real motion, no-slip checks and both travel limits" do
    attrs = "test/fixtures/figures/rack-program.json" |> File.read!() |> Jason.decode!()
    assert {:ok, source} = Source.new(attrs)
    assert {:ok, result} = Runner.check(Source.files(source))
    assert result.report["ok"], inspect(result.report)
    assert length(result.report["model_checks"]) >= 22
    assert Enum.all?(result.report["model_checks"], & &1["passed"])
    assert length(result.report["checks"]) == 5
    assert Enum.all?(result.report["checks"], & &1["passed"])
    assert result.report["animation_observed"]
    assert result.report["reduced_motion_stable"]
    refute result.report["mobile_framing"]["clipped"]
    assert result.report["errors"] == []
    assert result.report["network"] == []
    assert length(result.images) == 6
  end

  test "a drawing clipped inside its mobile SVG fails even without document overflow" do
    files = Map.update!(program(), "figure.mjs", &String.replace(&1, ~s(cx="50"), ~s(cx="95")))
    assert {:ok, result} = Runner.check(files)
    refute result.report["ok"]
    assert result.report["mobile_framing"]["clipped"]
    assert Enum.any?(result.report["errors"], &String.contains?(&1, "mobile drawing is clipped"))
    refute Map.has_key?(result, :bundle)
  end
end
