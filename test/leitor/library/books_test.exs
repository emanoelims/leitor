defmodule Leitor.Library.BooksTest do
  use Leitor.DataCase, async: true

  import Leitor.AccountsFixtures, only: [user_scope_fixture: 0]
  import Leitor.LibraryFixtures

  alias Leitor.Library
  alias Leitor.Library.Book
  alias Leitor.Library.Text

  defp extracted(chapters \\ nil) do
    chapters =
      chapters ||
        [
          %{id: Ecto.UUID.generate(version: 7), title: "One", depth: 0, body: "<p>First chapter.</p>"},
          %{id: Ecto.UUID.generate(version: 7), title: "Two", depth: 1, body: "<p>Second chapter.</p>"}
        ]

    %{title: "A Small Book", author: "Ada Writer", language: "pt-BR", identifier: "urn:1", chapters: chapters}
  end

  describe "create_book/2" do
    test "stores the book and its read-only chapters in reading order" do
      scope = user_scope_fixture()
      %{chapters: [first, second]} = book = extracted()

      assert {:ok, %Book{} = created} = Library.create_book(scope, book)
      assert created.title == "A Small Book"
      assert created.user_id == scope.user.id

      assert [%{id: first_id, position: 0}, %{id: second_id, position: 1}] = Library.book_chapters(scope, created)
      assert {first_id, second_id} == {first.id, second.id}

      text = Library.get_text!(scope, first.id)
      assert %Text{source: "epub", book_id: book_id, body: "<p>First chapter.</p>"} = text
      assert book_id == created.id

      assert %{"entries" => [%{"title" => "One", "depth" => 0}, %{"title" => "Two", "depth" => 1}]} = created.toc
    end

    test "rolls back the whole book when a chapter is invalid" do
      scope = user_scope_fixture()
      invalid = [%{id: Ecto.UUID.generate(version: 7), title: String.duplicate("t", 300), depth: 0, body: "<p>x</p>"}]

      assert {:error, %Ecto.Changeset{}} = Library.create_book(scope, extracted(invalid))
      assert Library.list_books(scope) == []
    end

    test "broadcasts to the owner" do
      scope = user_scope_fixture()
      Library.subscribe_texts(scope)

      {:ok, book} = Library.create_book(scope, extracted())
      assert_receive {:book_created, ^book}
    end
  end

  describe "reading" do
    setup do
      scope = user_scope_fixture()
      {:ok, book} = Library.create_book(scope, extracted())
      %{scope: scope, book: book, chapters: Library.book_chapters(scope, book)}
    end

    test "list_texts/1 leaves chapters out and list_books/1 counts them", %{scope: scope, chapters: [first | _]} do
      standalone = text_fixture(scope)

      assert Library.list_texts(scope) == [standalone]
      assert [%Book{chapter_count: 2, first_text_id: first_text_id}] = Library.list_books(scope)
      assert first_text_id == first.id
    end

    test "chapter_context/2 locates a chapter among its neighbours", %{scope: scope, chapters: [first, second]} do
      assert %{number: 1, previous: nil, next: next, chapters: [_, _]} =
               Library.chapter_context(scope, Library.get_text!(scope, first.id))

      assert next.id == second.id

      assert %{number: 2, previous: previous, next: nil} =
               Library.chapter_context(scope, Library.get_text!(scope, second.id))

      assert previous.id == first.id
      assert Library.chapter_context(scope, text_fixture(scope)) == nil
    end

    test "touch_book_progress/2 remembers the last chapter", %{scope: scope, book: book, chapters: [_, second]} do
      assert :ok = Library.touch_book_progress(scope, Library.get_text!(scope, second.id))
      assert Library.get_book!(scope, book.id).last_text_id == second.id
      assert :ok = Library.touch_book_progress(scope, text_fixture(scope))
    end

    test "books belong to their owner", %{book: book} do
      other = user_scope_fixture()

      assert_raise Ecto.NoResultsError, fn -> Library.get_book!(other, book.id) end
      assert Library.list_books(other) == []
      assert Library.book_chapters(other, book) == []
    end

    test "delete_book/2 removes the book with its chapters", %{scope: scope, book: book, chapters: [first | _]} do
      Library.subscribe_texts(scope)

      assert {:ok, _} = Library.delete_book(scope, book)
      assert_receive {:book_deleted, _}
      assert Library.list_books(scope) == []
      assert_raise Ecto.NoResultsError, fn -> Library.get_text!(scope, first.id) end
    end

    test "delete_book/2 removes a book even after a chapter was marked as last read", %{
      scope: scope,
      book: book,
      chapters: [first | _]
    } do
      Library.touch_book_progress(scope, Library.get_text!(scope, first.id))
      assert {:ok, _} = Library.delete_book(scope, Library.get_book!(scope, book.id))
    end
  end
end
