defmodule Leitor.LibraryTest do
  use Leitor.DataCase

  alias Leitor.Library

  describe "texts" do
    import Leitor.AccountsFixtures, only: [user_scope_fixture: 0]
    import Leitor.LibraryFixtures

    alias Leitor.Library.Text

    @invalid_attrs %{position: nil, title: nil, source: nil, body: nil}

    test "list_texts/1 returns all scoped texts" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      text = text_fixture(scope)
      other_text = text_fixture(other_scope)
      assert Library.list_texts(scope) == [text]
      assert Library.list_texts(other_scope) == [other_text]
    end

    test "get_text!/2 returns the text with given id" do
      scope = user_scope_fixture()
      text = text_fixture(scope)
      other_scope = user_scope_fixture()
      assert Library.get_text!(scope, text.id) == text
      assert_raise Ecto.NoResultsError, fn -> Library.get_text!(other_scope, text.id) end
    end

    test "create_text/2 with valid data creates a text" do
      valid_attrs = %{position: 42, title: "some title", source: "some source", body: "some body"}
      scope = user_scope_fixture()

      assert {:ok, %Text{} = text} = Library.create_text(scope, valid_attrs)
      assert text.position == 42
      assert text.title == "some title"
      assert text.source == "some source"
      assert text.body == "some body"
      assert text.user_id == scope.user.id
    end

    test "create_text/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Library.create_text(scope, @invalid_attrs)
    end

    test "update_text/3 with valid data updates the text" do
      scope = user_scope_fixture()
      text = text_fixture(scope)

      update_attrs = %{
        position: 43,
        title: "some updated title",
        source: "some updated source",
        body: "some updated body"
      }

      assert {:ok, %Text{} = text} = Library.update_text(scope, text, update_attrs)
      assert text.position == 43
      assert text.title == "some updated title"
      assert text.source == "some updated source"
      assert text.body == "some updated body"
    end

    test "update_text/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      text = text_fixture(scope)

      assert_raise MatchError, fn ->
        Library.update_text(other_scope, text, %{})
      end
    end

    test "update_text/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      text = text_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Library.update_text(scope, text, @invalid_attrs)
      assert text == Library.get_text!(scope, text.id)
    end

    test "delete_text/2 deletes the text" do
      scope = user_scope_fixture()
      text = text_fixture(scope)
      assert {:ok, %Text{}} = Library.delete_text(scope, text)
      assert_raise Ecto.NoResultsError, fn -> Library.get_text!(scope, text.id) end
    end

    test "delete_text/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      text = text_fixture(scope)
      assert_raise MatchError, fn -> Library.delete_text(other_scope, text) end
    end

    test "change_text/2 returns a text changeset" do
      scope = user_scope_fixture()
      text = text_fixture(scope)
      assert %Ecto.Changeset{} = Library.change_text(scope, text)
    end
  end
end
