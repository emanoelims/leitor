defmodule Leitor.Library do
  @moduledoc """
  The Library context.
  """

  import Ecto.Query, warn: false

  alias Leitor.Accounts.Scope
  alias Leitor.Library.Book
  alias Leitor.Library.BookAsset
  alias Leitor.Library.Epub
  alias Leitor.Library.Note
  alias Leitor.Library.Reading
  alias Leitor.Library.Storage
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

  Each chapter becomes a read-only text of source `"epub"` ordered by position, and the images the chapters
  show are stored with the book. If any part is invalid the whole book is rolled back.

  When object storage is configured the images are uploaded first and any that were uploaded are removed again
  if the book cannot be saved. If they cannot all be uploaded nothing is saved and the result is
  `{:error, :storage_unavailable}`. Without object storage the bytes are kept in the database.
  """
  @spec create_book(Scope.t(), Epub.book()) ::
          {:ok, Book.t()} | {:error, Ecto.Changeset.t() | :storage_unavailable}
  def create_book(%Scope{} = scope, %{chapters: chapters} = extracted) when chapters != [] do
    toc = %{
      "entries" => Enum.map(chapters, &%{"title" => &1.title, "text_id" => &1.id, "depth" => &1.depth})
    }

    attrs = extracted |> Map.take([:title, :author, :language, :identifier]) |> Map.put(:toc, toc)
    stored = Map.get(extracted, :assets, [])
    cover = extracted |> Map.get(:cover_asset_id) |> then(&if(&1 in Enum.map(stored, fn a -> a.id end), do: &1))

    with {:ok, assets} <- upload_assets(stored),
         {:ok, book} <- save_book(scope, attrs, cover, assets, chapters) do
      broadcast_text(scope, {:book_created, book})
      {:ok, book}
    end
  end

  defp save_book(scope, attrs, cover, assets, chapters) do
    result =
      Repo.transact(fn ->
        with {:ok, book} <- %Book{cover_asset_id: cover} |> Book.changeset(attrs, scope) |> Repo.insert(),
             :ok <- insert_assets(book, assets),
             :ok <- insert_chapters(scope, book, chapters) do
          {:ok, book}
        end
      end)

    # Objects uploaded for a book that was not saved would never be referenced again.
    with {:error, _} <- result do
      assets |> Enum.flat_map(&List.wrap(Map.get(&1, :storage_key))) |> Storage.delete_all()
      result
    end
  end

  # Without object storage the bytes stay on the asset and are saved with its row.
  defp upload_assets(assets) do
    if assets != [] and Storage.configured?() do
      results =
        assets
        |> Task.async_stream(&upload_asset/1, max_concurrency: 4, timeout: :infinity)
        |> Enum.map(fn {:ok, result} -> result end)

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, Enum.map(results, fn {:ok, asset} -> asset end)}
      else
        results |> Enum.flat_map(&uploaded_key/1) |> Storage.delete_all()
        {:error, :storage_unavailable}
      end
    else
      {:ok, assets}
    end
  end

  defp upload_asset(asset) do
    key = "book-assets/#{asset.id}"

    case Storage.put(key, asset.data, asset.content_type) do
      :ok -> {:ok, asset |> Map.delete(:data) |> Map.put(:storage_key, key)}
      {:error, _reason} = error -> error
    end
  end

  defp uploaded_key({:ok, %{storage_key: key}}), do: [key]
  defp uploaded_key(_failure), do: []

  defp insert_assets(book, assets) do
    now = DateTime.utc_now(:second)

    assets
    |> Enum.chunk_every(25)
    |> Enum.each(fn chunk ->
      rows =
        Enum.map(chunk, fn asset ->
          asset
          |> Map.take([:id, :content_type, :byte_size, :digest, :data, :storage_key])
          |> Map.merge(%{book_id: book.id, inserted_at: now})
        end)

      Repo.insert_all(BookAsset, rows, log: false)
    end)
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

  @doc """
  Fetches an image of a caller-owned book. Returns `:error` for unknown, malformed or other readers' images.
  """
  @spec get_book_asset(Scope.t(), term()) :: {:ok, BookAsset.t()} | :error
  def get_book_asset(%Scope{} = scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %BookAsset{} = asset <-
           Repo.one(
             from a in BookAsset,
               join: b in Book,
               on: b.id == a.book_id,
               where: a.id == ^id and b.user_id == ^scope.user.id,
               select: struct(a, [:id, :content_type, :digest, :data, :storage_key])
           ) do
      {:ok, asset}
    else
      _ -> :error
    end
  end

  @doc """
  Returns the bytes of an image, from the database or from object storage. A missing or altered object is
  `{:error, :unavailable}`, so a damaged store can never serve the wrong picture.
  """
  @spec asset_data(BookAsset.t()) :: {:ok, binary()} | {:error, :unavailable}
  def asset_data(%BookAsset{data: data}) when is_binary(data), do: {:ok, data}

  def asset_data(%BookAsset{storage_key: key, digest: digest}) when is_binary(key) do
    case Storage.get(key) do
      {:ok, data} -> if :crypto.hash(:sha256, data) == digest, do: {:ok, data}, else: {:error, :unavailable}
      {:error, _reason} -> {:error, :unavailable}
    end
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

  @doc "Deletes a book with its chapters, annotations, notes, shares and images, including stored objects."
  @spec delete_book(Scope.t(), Book.t()) :: {:ok, Book.t()} | {:error, Ecto.Changeset.t()}
  def delete_book(%Scope{} = scope, %Book{} = book) do
    true = book.user_id == scope.user.id

    keys =
      Repo.all(from a in BookAsset, where: a.book_id == ^book.id and not is_nil(a.storage_key), select: a.storage_key)

    with {:ok, book} <- Repo.delete(book) do
      Storage.delete_all(keys)
      broadcast_text(scope, {:book_deleted, book})
      {:ok, book}
    end
  end
end
