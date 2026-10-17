defmodule Leitor.Figures.Artifacts do
  @moduledoc "Ownership-scoped storage of immutable program revisions. Drafts retain evidence but cannot execute."
  import Ecto.Query

  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Artifact
  alias Leitor.Repo

  @doc "Stores one bounded revision after execution and visual review. Ownership is assigned by the caller's scope."
  @spec store(Scope.t(), map()) :: {:ok, Artifact.t()} | {:error, Ecto.Changeset.t()}
  def store(%Scope{user: %{id: user_id}}, attrs) do
    %Artifact{user_id: user_id}
    |> Ecto.Changeset.cast(attrs, [
      :title,
      :caption,
      :model,
      :source,
      :report,
      :bundle,
      :style,
      :preview,
      :digest,
      :status
    ])
    |> Ecto.Changeset.validate_required([:title, :caption, :model, :source, :report, :status])
    |> Ecto.Changeset.validate_inclusion(:status, ~w(draft ready))
    |> Ecto.Changeset.validate_length(:title, max: 100)
    |> Ecto.Changeset.validate_length(:caption, max: 600)
    |> validate_payload()
    |> Repo.insert(log: false)
  end

  defp validate_payload(changeset) do
    changeset =
      Enum.reduce([{:bundle, 1_000_000}, {:style, 100_000}, {:preview, 2_000_000}], changeset, fn {field, max}, acc ->
        Ecto.Changeset.validate_change(acc, field, &within_budget(&1, &2, max))
      end)

    changeset =
      Enum.reduce([{:source, 300_000}, {:report, 50_000}], changeset, fn {field, max}, acc ->
        Ecto.Changeset.validate_change(acc, field, &within_budget(&1, Jason.encode!(&2), max))
      end)

    case Ecto.Changeset.get_field(changeset, :status) do
      "ready" ->
        changeset = Ecto.Changeset.validate_required(changeset, [:bundle, :style, :preview])
        put_digest(changeset, Ecto.Changeset.get_field(changeset, :bundle))

      _ ->
        changeset
    end
  end

  defp put_digest(changeset, bundle) when is_binary(bundle),
    do: Ecto.Changeset.put_change(changeset, :digest, Base.encode16(:crypto.hash(:sha256, bundle), case: :lower))

  defp put_digest(changeset, _bundle), do: changeset

  defp within_budget(key, value, max),
    do: if(byte_size(value) <= max, do: [], else: [{key, "exceeds the storage budget"}])

  @doc "Fetches an executable revision owned by this account; malformed, missing and foreign IDs return nil."
  @spec get_ready(Scope.t(), term()) :: Artifact.t() | nil
  def get_ready(%Scope{user: %{id: user_id}}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.one(from a in Artifact, where: a.id == ^id and a.user_id == ^user_id and a.status == "ready")
      :error -> nil
    end
  end

  @doc "Fetches an owned ready or draft revision for an explicitly requested authoring continuation. It never grants reader execution."
  @spec get_revision(Scope.t(), term()) :: Artifact.t() | nil
  def get_revision(%Scope{user: %{id: user_id}}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.one(from a in Artifact, where: a.id == ^id and a.user_id == ^user_id)
      :error -> nil
    end
  end
end
