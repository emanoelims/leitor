defmodule Leitor.Library do
  @moduledoc """
  The Library context.
  """

  import Ecto.Query, warn: false

  alias Leitor.Accounts.Scope
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
  Returns the list of texts.

  """
  @spec list_texts(Scope.t()) :: [Text.t()]
  def list_texts(%Scope{} = scope) do
    Repo.all_by(Text, user_id: scope.user.id)
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
end
