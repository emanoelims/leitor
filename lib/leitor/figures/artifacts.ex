defmodule Leitor.Figures.Artifacts do
  @moduledoc "Ownership-scoped storage of immutable program revisions. Drafts retain evidence but cannot execute."
  import Ecto.Query

  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Artifact
  alias Leitor.Repo

  @doc "Stores one bounded revision after execution and visual review. Ownership is assigned by the caller's scope."
  @spec store(Scope.t(), map()) :: {:ok, Artifact.t()} | {:error, Ecto.Changeset.t()}
  def store(%Scope{user: %{id: user_id}} = scope, attrs) do
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
    |> put_parent(scope, Map.get(attrs, :parent_id))
    |> validate_payload()
    |> Repo.insert(log: false)
  end

  defp put_parent(changeset, _scope, nil), do: changeset

  defp put_parent(changeset, scope, id) do
    case get_ready(scope, id) do
      nil -> Ecto.Changeset.add_error(changeset, :parent_id, "must be an owned accepted revision")
      parent -> Ecto.Changeset.put_change(changeset, :parent_id, parent.id)
    end
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

  @doc "Lists the current revision and up to nineteen related accepted versions, including descendants so a restored version can return forward. Only safe metadata is selected; drafts, unrelated revisions and foreign accounts are excluded."
  @spec history(Scope.t(), term()) :: [map()]
  def history(%Scope{user: %{id: user_id}}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> expand_family(user_id, ancestors(user_id, id, 20))
      :error -> []
    end
  end

  defp expand_family(_user_id, []), do: []
  defp expand_family(_user_id, entries) when length(entries) >= 20, do: entries

  defp expand_family(user_id, entries) do
    ids = Enum.map(entries, & &1.id)
    remaining = 20 - length(entries)

    more =
      Repo.all(
        from a in Artifact,
          where: a.user_id == ^user_id and a.status == "ready" and a.parent_id in ^ids and a.id not in ^ids,
          order_by: [desc: a.inserted_at, desc: a.id],
          limit: ^remaining,
          select: merge(map(a, [:id, :title, :caption, :inserted_at]), %{profile: fragment("?->>'profile'", a.report)})
      )

    if more == [], do: entries, else: expand_family(user_id, entries ++ more)
  end

  defp ancestors(_user_id, nil, _remaining), do: []
  defp ancestors(_user_id, _id, 0), do: []

  defp ancestors(user_id, id, remaining) do
    entry =
      Repo.one(
        from a in Artifact,
          where: a.id == ^id and a.user_id == ^user_id and a.status == "ready",
          select:
            merge(map(a, [:id, :parent_id, :title, :caption, :inserted_at]), %{
              profile: fragment("?->>'profile'", a.report)
            })
      )

    if entry, do: [Map.delete(entry, :parent_id) | ancestors(user_id, entry.parent_id, remaining - 1)], else: []
  end

  @doc "Returns a reference to an owned accepted related version, without provider work. Unrelated, draft, malformed and foreign targets return an error."
  @spec restore_reference(Scope.t(), term(), term()) :: {:ok, map()} | {:error, :invalid_revision}
  def restore_reference(scope, current, target) do
    case Enum.find(history(scope, current), &(&1.id == target)) do
      nil ->
        {:error, :invalid_revision}

      entry ->
        {:ok,
         %{
           engine: "anatomy-program",
           version: 1,
           artifact_id: entry.id,
           title: entry.title,
           caption: entry.caption,
           profile: entry.profile || "visual_explainer"
         }}
    end
  end
end
