defmodule Leitor.LearningFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Leitor.Learning` context.
  """

  @doc """
  Generate a entry.
  """
  def entry_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        category: "some category",
        context: "some context",
        due_at: ~U[2026-10-07 06:23:00Z],
        interval: 42,
        meaning: "some meaning",
        status: "some status",
        term: "some term"
      })

    {:ok, entry} = Leitor.Learning.create_entry(scope, attrs)
    entry
  end

  @doc """
  Generate a attempt.
  """
  def attempt_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        content: "some content",
        duration: 42,
        kind: "some kind",
        result: %{}
      })

    {:ok, attempt} = Leitor.Learning.create_attempt(scope, attrs)
    attempt
  end
end
