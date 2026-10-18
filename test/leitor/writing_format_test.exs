defmodule Leitor.WritingFormatTest do
  use ExUnit.Case, async: true

  alias Leitor.WritingFormat

  test "three reviewed figure profiles are enabled and planned formats cannot bypass the catalog" do
    assert Enum.map(WritingFormat.options(), &elem(&1, 1)) ==
             ~w(visual_explainer scientific_diagram explanatory_illustration)

    assert WritingFormat.instruction("visual_explainer") =~ "mechanism"

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
