defmodule Mix.Tasks.LeitorAITest do
  use ExUnit.Case, async: true

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
end
