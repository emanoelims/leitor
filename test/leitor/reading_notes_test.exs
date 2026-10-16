defmodule Leitor.ReadingNotesTest do
  use Leitor.DataCase

  import Leitor.AccountsFixtures
  import Leitor.LibraryFixtures

  alias Leitor.Library
  alias Leitor.Library.Note
  alias Leitor.Library.Reading

  test "paragraphs retain their sentence anchors and original paragraph boundaries" do
    sentences = Reading.prepare("First sentence. Still here.\n\nA new paragraph!")
    assert [%{id: 0, sentences: [{_, 0}, {_, 1}]}, %{id: 1, sentences: [{_, 2}]}] = Reading.paragraphs(sentences)
    assert Enum.map(sentences, & &1.body) == ["First sentence.", "Still here.", "A new paragraph!"]
  end

  test "note ownership follows the parent reading and quotes come from stored text" do
    owner = user_scope_fixture()
    other = user_scope_fixture()
    text = text_fixture(owner, %{body: "First sentence. Second sentence."})

    assert {:ok, %Note{} = note} =
             Library.create_note(owner, text.id, %{
               sentence_index: 1,
               body: "Remember this.",
               quote: "forged",
               text_id: "forged"
             })

    assert note.quote == "Second sentence."
    assert note.text_id == text.id
    assert Library.list_notes(owner, text.id) == [note]
    assert Library.list_notes(other, text.id) == []

    assert_raise Ecto.NoResultsError, fn ->
      Library.create_note(other, text.id, %{sentence_index: 0, body: "No access"})
    end
  end

  test "invalid content and invalid anchors are recoverable and never insert notes" do
    scope = user_scope_fixture()
    text = text_fixture(scope)
    assert {:error, :invalid_anchor} = Library.create_note(scope, text.id, %{sentence_index: 100, body: "Too far"})

    for attrs <- [
          %{body: ""},
          %{sentence_index: -1, body: "No"},
          %{sentence_index: "invalid", body: "No"},
          %{sentence_index: 0, body: String.duplicate("a", 4001)},
          %{sentence_index: 0, body: "No", kind: "unknown"}
        ] do
      assert {:error, %Ecto.Changeset{}} = Library.create_note(scope, text.id, attrs)
    end

    assert Library.list_notes(scope, text.id) == []
  end

  test "saving session notes is atomic, and deleting a reading cascades its notes" do
    scope = user_scope_fixture()
    attrs = %{title: "My reading", body: "First.\n\nSecond.", source: "reading", position: 0}

    notes = [
      %{sentence_index: 0, body: "Personal thought"},
      %{sentence_index: 1, body: "Tutor answer", kind: "tutor", question: "Why?", references: [1, 2]}
    ]

    assert {:ok, text} = Library.create_text_with_notes(scope, attrs, notes)
    assert [%{body: "Personal thought"}, %{references: [1, 2]}] = Library.list_notes(scope, text.id)

    assert {:error, :invalid_anchor} =
             Library.create_text_with_notes(scope, attrs, [%{sentence_index: 99, body: "Invalid"}])

    assert Library.list_texts(scope) == [text]
    assert {:error, %Ecto.Changeset{}} = Library.create_text_with_notes(scope, %{attrs | body: ""}, notes)
    assert {:error, %Ecto.Changeset{}} = Library.create_text_with_notes(scope, attrs, [%{sentence_index: 0, body: ""}])
    assert Library.list_texts(scope) == [text]
    assert {:ok, _} = Library.delete_text(scope, text)
    assert Library.list_notes(scope, text.id) == []
  end
end
