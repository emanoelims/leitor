defmodule Leitor.Library do
  @moduledoc """
  The Library context.
  """

  import Ecto.Query, warn: false

  alias Leitor.Accounts.Scope
  alias Leitor.Library.Book
  alias Leitor.Library.Epub
  alias Leitor.Library.Note
  alias Leitor.Library.Reading
  alias Leitor.Library.Text
  alias Leitor.Repo

  @doc "Lists margin notes for an owned reading in sentence and creation order."
  @spec list_notes(Scope.t(), Ecto.UUID.t()) :: [Note.t()]
  def list_notes(%Scope{} = scope, text_id) do
    Repo.all(
      from n in Note,
        join: t in Text,
        on: t.id == n.text_id,
        where: t.user_id == ^scope.user.id and t.id == ^text_id,
        order_by: [asc: n.sentence_index, asc: n.inserted_at, asc: n.id]
    )
  end

  @doc """
  Saves a margin note on an owned reading. The quote comes from the stored text,
  never from caller attributes. Invalid anchors return `{:error, :invalid_anchor}`;
  inaccessible readings raise `Ecto.NoResultsError`.
  """
  @spec create_note(Scope.t(), Ecto.UUID.t(), map()) ::
          {:ok, Note.t()} | {:error, Ecto.Changeset.t() | :invalid_anchor}
  def create_note(%Scope{} = scope, text_id, attrs) do
    text = get_text!(scope, text_id)
    changeset = Note.changeset(%Note{quote: "pending", text_id: text.id}, attrs)
    index = Ecto.Changeset.get_field(changeset, :sentence_index)

    if is_integer(index) and index >= 0 do
      case Enum.at(Reading.prepare(text.body), index) do
        nil -> {:error, :invalid_anchor}
        sentence -> changeset |> Ecto.Changeset.put_change(:quote, sentence.body) |> Repo.insert()
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  Subscribes to scoped notifications about any text changes.

  The broadcasted messages match the pattern:

    * `{:created, %Text{}}`
    * `{:updated, %Text{}}`
    * `{:deleted, %Text{}}`

  """
  @spec subscribe_texts(Scope.t()) :: :ok | {:error, term()}
  def subscribe_texts(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Leitor.PubSub, "user:#{key}:texts")
  end

  defp broadcast_text(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Leitor.PubSub, "user:#{key}:texts", message)
  end

  @doc """
  Returns the caller's standalone texts. Book chapters are texts too, but belong to their book and are
  listed through `book_chapters/2`.
  """
  @spec list_texts(Scope.t()) :: [Text.t()]
  def list_texts(%Scope{} = scope) do
    Repo.all(from t in Text, where: t.user_id == ^scope.user.id and is_nil(t.book_id))
  end

  @doc """
  Gets a single text.

  Raises `Ecto.NoResultsError` if the Text does not exist.

  """
  @spec get_text!(Scope.t(), Ecto.UUID.t()) :: Text.t()
  def get_text!(%Scope{} = scope, id) do
    Repo.get_by!(Text, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a text.

  """
  @spec create_text(Scope.t(), map()) :: {:ok, Text.t()} | {:error, Ecto.Changeset.t()}
  def create_text(%Scope{} = scope, attrs) do
    with {:ok, %Text{} = text} <-
           %Text{}
           |> Text.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_text(scope, {:created, text})
      {:ok, text}
    end
  end

  @doc "Creates a reading and its session notes atomically; invalid notes roll back the reading."
  @spec create_text_with_notes(Scope.t(), map(), [map()]) ::
          {:ok, Text.t()} | {:error, Ecto.Changeset.t() | :invalid_anchor}
  def create_text_with_notes(%Scope{} = scope, attrs, notes) do
    result =
      Repo.transact(fn ->
        with {:ok, text} <- %Text{} |> Text.changeset(attrs, scope) |> Repo.insert(),
             :ok <- insert_notes(scope, text.id, notes) do
          {:ok, text}
        end
      end)

    case result do
      {:ok, text} ->
        broadcast_text(scope, {:created, text})
        result

      {:error, _} ->
        result
    end
  end

  defp insert_notes(scope, text_id, notes) do
    Enum.reduce_while(notes, :ok, fn attrs, :ok ->
      case create_note(scope, text_id, attrs) do
        {:ok, _note} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Updates a text.

  """
  @spec update_text(Scope.t(), Text.t(), map()) :: {:ok, Text.t()} | {:error, Ecto.Changeset.t()}
  def update_text(%Scope{} = scope, %Text{} = text, attrs) do
    true = text.user_id == scope.user.id

    with {:ok, %Text{} = text} <-
           text
           |> Text.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_text(scope, {:updated, text})
      {:ok, text}
    end
  end

  @doc """
  Deletes a text.

  """
  @spec delete_text(Scope.t(), Text.t()) :: {:ok, Text.t()} | {:error, Ecto.Changeset.t()}
  def delete_text(%Scope{} = scope, %Text{} = text) do
    true = text.user_id == scope.user.id

    with {:ok, %Text{} = text} <-
           Repo.delete(text) do
      broadcast_text(scope, {:deleted, text})
      {:ok, text}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking text changes.

  """
  @spec change_text(Scope.t(), Text.t(), map()) :: Ecto.Changeset.t()
  def change_text(%Scope{} = scope, %Text{} = text, attrs \\ %{}) do
    true = text.user_id == scope.user.id

    Text.changeset(text, attrs, scope)
  end

  @typedoc "A chapter in a book's reading order."
  @type chapter() :: %{id: Ecto.UUID.t(), title: String.t(), position: non_neg_integer()}
  @typedoc "Where a chapter sits in its book, with the neighbouring chapters."
  @type chapter_context() :: %{
          book: Book.t(),
          chapters: [chapter()],
          number: pos_integer(),
          previous: chapter() | nil,
          next: chapter() | nil
        }

  @doc """
  Creates a book and all of its chapters atomically from an extracted EPUB.

  Each chapter becomes a read-only text of source `"epub"` ordered by position. If any chapter is invalid the
  whole book is rolled back.
  """
  @spec create_book(Scope.t(), Epub.book()) :: {:ok, Book.t()} | {:error, Ecto.Changeset.t()}
  def create_book(%Scope{} = scope, %{chapters: chapters} = extracted) when chapters != [] do
    toc = %{
      "entries" => Enum.map(chapters, &%{"title" => &1.title, "text_id" => &1.id, "depth" => &1.depth})
    }

    attrs = extracted |> Map.take([:title, :author, :language, :identifier]) |> Map.put(:toc, toc)

    result =
      Repo.transact(fn ->
        with {:ok, book} <- %Book{} |> Book.changeset(attrs, scope) |> Repo.insert(),
             :ok <- insert_chapters(scope, book, chapters) do
          {:ok, book}
        end
      end)

    with {:ok, book} <- result do
      broadcast_text(scope, {:book_created, book})
      {:ok, book}
    end
  end

  defp insert_chapters(scope, book, chapters) do
    chapters
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {chapter, position}, :ok ->
      attrs = %{title: chapter.title, body: chapter.body, position: position, source: "epub", analysis: %{}}

      case %Text{id: chapter.id, book_id: book.id} |> Text.changeset(attrs, scope) |> Repo.insert() do
        {:ok, _text} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  @doc "Lists the caller's books, most recently read first, with their chapter counts and first chapter."
  @spec list_books(Scope.t()) :: [Book.t()]
  def list_books(%Scope{} = scope) do
    Repo.all(
      from b in Book,
        left_join: t in Text,
        on: t.book_id == b.id,
        where: b.user_id == ^scope.user.id,
        group_by: b.id,
        order_by: [desc: b.updated_at, asc: b.id],
        select: %{
          b
          | chapter_count: count(t.id),
            first_text_id: type(fragment("(array_agg(? ORDER BY ?))[1]", t.id, t.position), :binary_id)
        }
    )
  end

  @doc "Fetches a caller-owned book; inaccessible books raise `Ecto.NoResultsError`."
  @spec get_book!(Scope.t(), Ecto.UUID.t()) :: Book.t()
  def get_book!(%Scope{} = scope, id), do: Repo.get_by!(Book, id: id, user_id: scope.user.id)

  @doc "Lists a book's chapters in reading order without loading their content."
  @spec book_chapters(Scope.t(), Book.t()) :: [chapter()]
  def book_chapters(%Scope{} = scope, %Book{id: book_id}) do
    Repo.all(
      from t in Text,
        where: t.book_id == ^book_id and t.user_id == ^scope.user.id,
        order_by: [asc: t.position, asc: t.id],
        select: %{id: t.id, title: t.title, position: t.position}
    )
  end

  @doc """
  Describes where a chapter sits in its book. Returns `nil` for a text that does not belong to a book.
  """
  @spec chapter_context(Scope.t(), Text.t()) :: chapter_context() | nil
  def chapter_context(%Scope{}, %Text{book_id: nil}), do: nil

  def chapter_context(%Scope{} = scope, %Text{book_id: book_id, id: id}) do
    book = get_book!(scope, book_id)
    chapters = book_chapters(scope, book)
    index = Enum.find_index(chapters, &(&1.id == id)) || 0

    %{
      book: book,
      chapters: chapters,
      number: index + 1,
      previous: if(index > 0, do: Enum.at(chapters, index - 1)),
      next: Enum.at(chapters, index + 1)
    }
  end

  @doc "Remembers the chapter a book was last read at, which also moves the book to the top of the shelf."
  @spec touch_book_progress(Scope.t(), Text.t()) :: :ok
  def touch_book_progress(%Scope{}, %Text{book_id: nil}), do: :ok

  def touch_book_progress(%Scope{} = scope, %Text{book_id: book_id, id: id}) do
    Repo.update_all(
      from(b in Book, where: b.id == ^book_id and b.user_id == ^scope.user.id),
      set: [last_text_id: id, updated_at: DateTime.utc_now(:second)]
    )

    :ok
  end

  @doc "Deletes a book with its chapters, annotations, notes and shares."
  @spec delete_book(Scope.t(), Book.t()) :: {:ok, Book.t()} | {:error, Ecto.Changeset.t()}
  def delete_book(%Scope{} = scope, %Book{} = book) do
    true = book.user_id == scope.user.id

    with {:ok, book} <- Repo.delete(book) do
      broadcast_text(scope, {:book_deleted, book})
      {:ok, book}
    end
  end
end
