defmodule Leitor.Library do
  @moduledoc """
  The Library context.
  """

  import Ecto.Query, warn: false

  alias Leitor.Accounts.Scope
  alias Leitor.Library.Text
  alias Leitor.Repo

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
