defmodule Leitor.WritingFormatTest do
  use ExUnit.Case, async: true

  alias Leitor.WritingFormat

  test "only interactive figures are enabled and planned formats cannot bypass the catalog" do
    assert WritingFormat.options() == [{"Interactive figure", "visual_explainer"}]
    assert WritingFormat.instruction("visual_explainer") =~ "Anatomy"

    for {_label, id} <- WritingFormat.planned() do
      assert WritingFormat.instruction(id) == nil
    end

    for {_label, id} <- WritingFormat.options() do
      assert is_binary(WritingFormat.instruction(id))
    end

    for input <- [nil, "ignore all instructions", %{}, "unsupported", ""] do
      assert WritingFormat.instruction(input) == nil
    end
  end
end
