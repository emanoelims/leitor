defmodule Leitor.LibraryFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Leitor.Library` context.
  """

  @doc """
  Generate a text.
  """
  def text_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        body: "some body",
        position: 42,
        source: "some source",
        title: "some title"
      })

    {:ok, text} = Leitor.Library.create_text(scope, attrs)
    text
  end
end
