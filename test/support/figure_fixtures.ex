defmodule Leitor.FigureFixtures do
  @moduledoc false
  def figure_response(before_text \\ "A small workshop.") do
    %{
      "before" => before_text,
      "figure" => Jason.decode!(File.read!("test/fixtures/figures/gears.json")),
      "after" => "Pause the second station and watch the queue."
    }
  end

  def figure_markdown(before_text \\ "A small workshop.") do
    response = figure_response(before_text)

    response["before"] <>
      "\n\n```leitor-figure\n" <> Jason.encode!(response["figure"]) <> "\n```\n\n" <> response["after"]
  end
end
