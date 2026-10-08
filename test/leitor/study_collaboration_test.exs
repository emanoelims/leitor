defmodule Leitor.StudyCollaborationTest do
  use Leitor.DataCase, async: true

  import Leitor.AccountsFixtures

  alias Leitor.Accounts.Scope
  alias Leitor.Study

  test "invitations are generated, unique, and scoped CRUD never grants guests ownership" do
    host = Scope.for_user(user_fixture())
    guest = Scope.for_user(user_fixture())

    {:ok, room} =
      Study.open_room(host, %{
        "title" => "A club",
        "body" => "First. Second.",
        "invite_code" => "chosen",
        "user_id" => guest.user.id
      })

    assert String.length(room.invite_code) == 32
    assert room.user_id == host.user.id
    assert String.at(room.id, 14) == "7"
    assert {:ok, ^room} = Study.join_room(guest, room.invite_code)
    assert [] == Study.list_rooms(guest)
    assert_raise Ecto.NoResultsError, fn -> Study.get_room!(guest, room.id) end
    assert {:error, :forbidden} = Study.advance_room(guest, room.invite_code, :next)
    assert {:ok, %{position: 1}} = Study.advance_room(host, room.invite_code, :next)
    assert {:ok, %{position: 1}} = Study.advance_room(host, room.invite_code, :next)
    assert {:ok, %{position: 0}} = Study.advance_room(host, room.invite_code, :previous)
    assert {:error, :invalid_message} = Study.send_message(guest, room.invite_code, "  ")
    assert {:error, :invalid_message} = Study.send_message(guest, room.invite_code, String.duplicate("x", 501))
    assert {:error, :not_found} = Study.send_message(guest, "missing", "Hello")
    {:ok, _} = Study.subscribe_room(guest, room.invite_code)
    assert :ok = Study.send_message(guest, room.invite_code, "Hello")
    assert_receive {:room_message, %{body: "Hello", name: name}}
    refute name =~ guest.user.email
  end
end
