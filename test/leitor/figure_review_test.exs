defmodule Leitor.FigureReviewTest do
  use ExUnit.Case, async: true

  alias Leitor.Figures.Review

  test "missing and oversized evidence cannot approve a figure" do
    assert {:error, _} = Review.new(%{accept: true, critique: "Looks good"})

    assert {:error, _} =
             Review.new(%{accept: true, critique: "Fine", explanation_consistent: true, explanation_evidence: " "})

    assert {:error, _} =
             Review.new(%{
               accept: true,
               critique: "Fine",
               explanation_consistent: true,
               explanation_evidence: String.duplicate("a", 2001)
             })

    assert {:ok, %{accept: false, critique: critique}} =
             Review.new(%{
               accept: true,
               critique: "Mechanism works",
               explanation_consistent: false,
               explanation_evidence: "The stated derivative is inverted"
             })

    assert critique =~ "inverted"
  end
end
