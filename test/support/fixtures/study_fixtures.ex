defmodule Leitor.StudyFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Leitor.Study` context.
  """

  @doc """
  Generate a room.
  """
  def room_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        body: "some body",
        invite_code: "invite-#{System.unique_integer([:positive])}",
        position: 42,
        title: "some title"
      })

    {:ok, room} = Leitor.Study.create_room(scope, attrs)
    room
  end
end
