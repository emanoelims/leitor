defmodule Leitor.StudyTest do
  use Leitor.DataCase

  alias Leitor.Study

  describe "rooms" do
    import Leitor.AccountsFixtures, only: [user_scope_fixture: 0]
    import Leitor.StudyFixtures

    alias Leitor.Study.Room

    @invalid_attrs %{position: nil, title: nil, body: nil, invite_code: nil}

    test "list_rooms/1 returns all scoped rooms" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      room = room_fixture(scope)
      other_room = room_fixture(other_scope)
      assert Study.list_rooms(scope) == [room]
      assert Study.list_rooms(other_scope) == [other_room]
    end

    test "get_room!/2 returns the room with given id" do
      scope = user_scope_fixture()
      room = room_fixture(scope)
      other_scope = user_scope_fixture()
      assert Study.get_room!(scope, room.id) == room
      assert_raise Ecto.NoResultsError, fn -> Study.get_room!(other_scope, room.id) end
    end

    test "create_room/2 with valid data creates a room" do
      valid_attrs = %{position: 42, title: "some title", body: "some body", invite_code: "some invite_code"}
      scope = user_scope_fixture()

      assert {:ok, %Room{} = room} = Study.create_room(scope, valid_attrs)
      assert room.position == 42
      assert room.title == "some title"
      assert room.body == "some body"
      assert room.invite_code == "some invite_code"
      assert room.user_id == scope.user.id
    end

    test "create_room/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Study.create_room(scope, @invalid_attrs)
    end

    test "update_room/3 with valid data updates the room" do
      scope = user_scope_fixture()
      room = room_fixture(scope)

      update_attrs = %{
        position: 43,
        title: "some updated title",
        body: "some updated body",
        invite_code: "some updated invite_code"
      }

      assert {:ok, %Room{} = room} = Study.update_room(scope, room, update_attrs)
      assert room.position == 43
      assert room.title == "some updated title"
      assert room.body == "some updated body"
      assert room.invite_code == "some updated invite_code"
    end

    test "update_room/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      room = room_fixture(scope)

      assert_raise MatchError, fn ->
        Study.update_room(other_scope, room, %{})
      end
    end

    test "update_room/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      room = room_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Study.update_room(scope, room, @invalid_attrs)
      assert room == Study.get_room!(scope, room.id)
    end

    test "delete_room/2 deletes the room" do
      scope = user_scope_fixture()
      room = room_fixture(scope)
      assert {:ok, %Room{}} = Study.delete_room(scope, room)
      assert_raise Ecto.NoResultsError, fn -> Study.get_room!(scope, room.id) end
    end

    test "delete_room/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      room = room_fixture(scope)
      assert_raise MatchError, fn -> Study.delete_room(other_scope, room) end
    end

    test "change_room/2 returns a room changeset" do
      scope = user_scope_fixture()
      room = room_fixture(scope)
      assert %Ecto.Changeset{} = Study.change_room(scope, room)
    end
  end
end
