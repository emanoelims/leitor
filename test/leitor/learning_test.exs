defmodule Leitor.LearningTest do
  use Leitor.DataCase

  alias Leitor.AccountsFixtures
  alias Leitor.Learning
  alias Leitor.Learning.Attempt

  describe "entries" do
    import AccountsFixtures, only: [user_scope_fixture: 0]
    import Leitor.LearningFixtures

    alias Leitor.Learning.Entry

    @invalid_attrs %{status: nil, term: nil, context: nil, category: nil, meaning: nil, interval: nil, due_at: nil}

    test "list_entries/1 returns all scoped entries" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      entry = entry_fixture(scope)
      other_entry = entry_fixture(other_scope)
      assert Learning.list_entries(scope) == [entry]
      assert Learning.list_entries(other_scope) == [other_entry]
    end

    test "get_entry!/2 returns the entry with given id" do
      scope = user_scope_fixture()
      entry = entry_fixture(scope)
      other_scope = user_scope_fixture()
      assert Learning.get_entry!(scope, entry.id) == entry
      assert_raise Ecto.NoResultsError, fn -> Learning.get_entry!(other_scope, entry.id) end
    end

    test "create_entry/2 with valid data creates a entry" do
      valid_attrs = %{
        status: "some status",
        term: "some term",
        context: "some context",
        category: "some category",
        meaning: "some meaning",
        interval: 42,
        due_at: ~U[2026-10-07 06:23:00Z]
      }

      scope = user_scope_fixture()

      assert {:ok, %Entry{} = entry} = Learning.create_entry(scope, valid_attrs)
      assert entry.status == "some status"
      assert entry.term == "some term"
      assert entry.context == "some context"
      assert entry.category == "some category"
      assert entry.meaning == "some meaning"
      assert entry.interval == 42
      assert entry.due_at == ~U[2026-10-07 06:23:00Z]
      assert entry.user_id == scope.user.id
    end

    test "create_entry/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Learning.create_entry(scope, @invalid_attrs)
    end

    test "update_entry/3 with valid data updates the entry" do
      scope = user_scope_fixture()
      entry = entry_fixture(scope)

      update_attrs = %{
        status: "some updated status",
        term: "some updated term",
        context: "some updated context",
        category: "some updated category",
        meaning: "some updated meaning",
        interval: 43,
        due_at: ~U[2026-10-08 06:23:00Z]
      }

      assert {:ok, %Entry{} = entry} = Learning.update_entry(scope, entry, update_attrs)
      assert entry.status == "some updated status"
      assert entry.term == "some updated term"
      assert entry.context == "some updated context"
      assert entry.category == "some updated category"
      assert entry.meaning == "some updated meaning"
      assert entry.interval == 43
      assert entry.due_at == ~U[2026-10-08 06:23:00Z]
    end

    test "update_entry/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      entry = entry_fixture(scope)

      assert_raise MatchError, fn ->
        Learning.update_entry(other_scope, entry, %{})
      end
    end

    test "update_entry/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      entry = entry_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Learning.update_entry(scope, entry, @invalid_attrs)
      assert entry == Learning.get_entry!(scope, entry.id)
    end

    test "delete_entry/2 deletes the entry" do
      scope = user_scope_fixture()
      entry = entry_fixture(scope)
      assert {:ok, %Entry{}} = Learning.delete_entry(scope, entry)
      assert_raise Ecto.NoResultsError, fn -> Learning.get_entry!(scope, entry.id) end
    end

    test "delete_entry/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      entry = entry_fixture(scope)
      assert_raise MatchError, fn -> Learning.delete_entry(other_scope, entry) end
    end

    test "change_entry/2 returns a entry changeset" do
      scope = user_scope_fixture()
      entry = entry_fixture(scope)
      assert %Ecto.Changeset{} = Learning.change_entry(scope, entry)
    end
  end

  describe "attempts" do
    import AccountsFixtures, only: [user_scope_fixture: 0]
    import Leitor.LearningFixtures

    @invalid_attrs %{result: nil, kind: nil, content: nil, duration: nil}

    test "list_attempts/1 returns all scoped attempts" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      attempt = attempt_fixture(scope)
      other_attempt = attempt_fixture(other_scope)
      assert Learning.list_attempts(scope) == [attempt]
      assert Learning.list_attempts(other_scope) == [other_attempt]
    end

    test "get_attempt!/2 returns the attempt with given id" do
      scope = user_scope_fixture()
      attempt = attempt_fixture(scope)
      other_scope = user_scope_fixture()
      assert Learning.get_attempt!(scope, attempt.id) == attempt
      assert_raise Ecto.NoResultsError, fn -> Learning.get_attempt!(other_scope, attempt.id) end
    end

    test "create_attempt/2 with valid data creates a attempt" do
      valid_attrs = %{result: %{}, kind: "some kind", content: "some content", duration: 42}
      scope = user_scope_fixture()

      assert {:ok, %Attempt{} = attempt} = Learning.create_attempt(scope, valid_attrs)
      assert attempt.result == %{}
      assert attempt.kind == "some kind"
      assert attempt.content == "some content"
      assert attempt.duration == 42
      assert attempt.user_id == scope.user.id
    end

    test "create_attempt/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Learning.create_attempt(scope, @invalid_attrs)
    end

    test "update_attempt/3 with valid data updates the attempt" do
      scope = user_scope_fixture()
      attempt = attempt_fixture(scope)
      update_attrs = %{result: %{}, kind: "some updated kind", content: "some updated content", duration: 43}

      assert {:ok, %Attempt{} = attempt} = Learning.update_attempt(scope, attempt, update_attrs)
      assert attempt.result == %{}
      assert attempt.kind == "some updated kind"
      assert attempt.content == "some updated content"
      assert attempt.duration == 43
    end

    test "update_attempt/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      attempt = attempt_fixture(scope)

      assert_raise MatchError, fn ->
        Learning.update_attempt(other_scope, attempt, %{})
      end
    end

    test "update_attempt/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      attempt = attempt_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Learning.update_attempt(scope, attempt, @invalid_attrs)
      assert attempt == Learning.get_attempt!(scope, attempt.id)
    end

    test "delete_attempt/2 deletes the attempt" do
      scope = user_scope_fixture()
      attempt = attempt_fixture(scope)
      assert {:ok, %Attempt{}} = Learning.delete_attempt(scope, attempt)
      assert_raise Ecto.NoResultsError, fn -> Learning.get_attempt!(scope, attempt.id) end
    end

    test "delete_attempt/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      attempt = attempt_fixture(scope)
      assert_raise MatchError, fn -> Learning.delete_attempt(other_scope, attempt) end
    end

    test "change_attempt/2 returns a attempt changeset" do
      scope = user_scope_fixture()
      attempt = attempt_fixture(scope)
      assert %Ecto.Changeset{} = Learning.change_attempt(scope, attempt)
    end
  end

  test "review scheduling records one attempt and publishes the committed resources" do
    scope = AccountsFixtures.user_scope_fixture()

    {:ok, entry} =
      Learning.save_word(scope, %{term: "went", meaning: "foi", category: "verb", context: "She went yesterday."})

    :ok = Learning.subscribe_entries(scope)
    :ok = Learning.subscribe_attempts(scope)
    {:ok, reviewed} = Learning.rate(scope, entry.id, "good")
    assert reviewed.interval == 86_400
    assert_receive {:updated, ^reviewed}
    assert_receive {:created, %Attempt{kind: "review", result: %{rating: "good"}} = attempt}
    assert Learning.get_entry!(scope, reviewed.id) == reviewed
    assert Learning.get_attempt!(scope, attempt.id).result == %{"rating" => "good"}
    refute_receive {:updated, _}
    {:ok, reviewed} = Learning.rate(scope, entry.id, "easy")
    assert reviewed.interval == 345_600
    {:ok, reviewed} = Learning.rate(scope, entry.id, "hard")
    assert reviewed.interval == 480
    {:ok, reviewed} = Learning.rate(scope, entry.id, "again")
    assert reviewed.interval == 60
    assert length(Learning.recent_attempts(scope)) == 4
  end
end
