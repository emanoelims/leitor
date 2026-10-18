defmodule Mix.Tasks.LeitorAITest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Leitor.Figure.Evaluate

  test "development credential import and paid preview commands fail closed outside development" do
    for task <- [
          Mix.Tasks.Leitor.Ai.Configure,
          Mix.Tasks.Leitor.Ai.Preview,
          Mix.Tasks.Leitor.Figure.Check,
          Mix.Tasks.Leitor.Figure.Curate
        ] do
      assert_raise Mix.Error, "This task is available only in development", fn -> task.run([]) end
    end
  end

  test "quality briefs are inspectable without provider use and paid execution stays development only" do
    output = ExUnit.CaptureIO.capture_io(fn -> Evaluate.run(["--list"]) end)
    assert output =~ "optical-refraction"
    assert output =~ "scientific_diagram"
    output = ExUnit.CaptureIO.capture_io(fn -> Evaluate.run(["--case", "lunar-phases"]) end)
    assert output =~ "fases da Lua"
    assert_raise Mix.Error, fn -> Evaluate.run(["--case", "unknown", "--generate"]) end

    ExUnit.CaptureIO.capture_io(fn ->
      assert_raise Mix.Error, "Paid quality evaluation is development only", fn ->
        Evaluate.run(["--case", "lunar-phases", "--generate", "--user-id", Ecto.UUID.generate()])
      end
    end)
  end
end
