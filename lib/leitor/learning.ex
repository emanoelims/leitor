defmodule Leitor.Learning do
  @moduledoc """
  The Learning context.
  """

  import Ecto.Query, warn: false

  alias Leitor.Accounts.Scope
  alias Leitor.Learning.Attempt
  alias Leitor.Learning.Entry
  alias Leitor.Repo

  @doc """
  Subscribes to scoped notifications about any entry changes.

  The broadcasted messages match the pattern:

    * `{:created, %Entry{}}`
    * `{:updated, %Entry{}}`
    * `{:deleted, %Entry{}}`

  """
  @spec subscribe_entries(Scope.t()) :: :ok | {:error, term()}
  def subscribe_entries(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Leitor.PubSub, "user:#{key}:entries")
  end

  defp broadcast_entry(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Leitor.PubSub, "user:#{key}:entries", message)
  end

  @doc """
  Returns the list of entries.

  """
  @spec list_entries(Scope.t()) :: [Entry.t()]
  def list_entries(%Scope{} = scope) do
    Repo.all_by(Entry, user_id: scope.user.id)
  end

  @doc """
  Gets a single entry.

  Raises `Ecto.NoResultsError` if the Entry does not exist.

  """
  @spec get_entry!(Scope.t(), Ecto.UUID.t()) :: Entry.t()
  def get_entry!(%Scope{} = scope, id) do
    Repo.get_by!(Entry, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a entry.

  """
  @spec create_entry(Scope.t(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def create_entry(%Scope{} = scope, attrs) do
    with {:ok, %Entry{} = entry} <-
           %Entry{}
           |> Entry.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_entry(scope, {:created, entry})
      {:ok, entry}
    end
  end

  @doc """
  Updates a entry.

  """
  @spec update_entry(Scope.t(), Entry.t(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def update_entry(%Scope{} = scope, %Entry{} = entry, attrs) do
    true = entry.user_id == scope.user.id

    with {:ok, %Entry{} = entry} <-
           entry
           |> Entry.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_entry(scope, {:updated, entry})
      {:ok, entry}
    end
  end

  @doc """
  Deletes a entry.

  """
  @spec delete_entry(Scope.t(), Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def delete_entry(%Scope{} = scope, %Entry{} = entry) do
    true = entry.user_id == scope.user.id

    with {:ok, %Entry{} = entry} <-
           Repo.delete(entry) do
      broadcast_entry(scope, {:deleted, entry})
      {:ok, entry}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking entry changes.

  """
  @spec change_entry(Scope.t(), Entry.t(), map()) :: Ecto.Changeset.t()
  def change_entry(%Scope{} = scope, %Entry{} = entry, attrs \\ %{}) do
    true = entry.user_id == scope.user.id

    Entry.changeset(entry, attrs, scope)
  end

  @doc """
  Subscribes to scoped notifications about any attempt changes.

  The broadcasted messages match the pattern:

    * `{:created, %Attempt{}}`
    * `{:updated, %Attempt{}}`
    * `{:deleted, %Attempt{}}`

  """
  @spec subscribe_attempts(Scope.t()) :: :ok | {:error, term()}
  def subscribe_attempts(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Leitor.PubSub, "user:#{key}:attempts")
  end

  defp broadcast_attempt(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Leitor.PubSub, "user:#{key}:attempts", message)
  end

  @doc """
  Returns the list of attempts.

  """
  @spec list_attempts(Scope.t()) :: [Attempt.t()]
  def list_attempts(%Scope{} = scope) do
    Repo.all_by(Attempt, user_id: scope.user.id)
  end

  @doc """
  Gets a single attempt.

  Raises `Ecto.NoResultsError` if the Attempt does not exist.

  """
  @spec get_attempt!(Scope.t(), Ecto.UUID.t()) :: Attempt.t()
  def get_attempt!(%Scope{} = scope, id) do
    Repo.get_by!(Attempt, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a attempt.

  """
  @spec create_attempt(Scope.t(), map()) :: {:ok, Attempt.t()} | {:error, Ecto.Changeset.t()}
  def create_attempt(%Scope{} = scope, attrs) do
    with {:ok, %Attempt{} = attempt} <-
           %Attempt{}
           |> Attempt.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_attempt(scope, {:created, attempt})
      {:ok, attempt}
    end
  end

  @doc """
  Updates a attempt.

  """
  @spec update_attempt(Scope.t(), Attempt.t(), map()) :: {:ok, Attempt.t()} | {:error, Ecto.Changeset.t()}
  def update_attempt(%Scope{} = scope, %Attempt{} = attempt, attrs) do
    true = attempt.user_id == scope.user.id

    with {:ok, %Attempt{} = attempt} <-
           attempt
           |> Attempt.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_attempt(scope, {:updated, attempt})
      {:ok, attempt}
    end
  end

  @doc """
  Deletes a attempt.

  """
  @spec delete_attempt(Scope.t(), Attempt.t()) :: {:ok, Attempt.t()} | {:error, Ecto.Changeset.t()}
  def delete_attempt(%Scope{} = scope, %Attempt{} = attempt) do
    true = attempt.user_id == scope.user.id

    with {:ok, %Attempt{} = attempt} <-
           Repo.delete(attempt) do
      broadcast_attempt(scope, {:deleted, attempt})
      {:ok, attempt}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking attempt changes.

  """
  @spec change_attempt(Scope.t(), Attempt.t(), map()) :: Ecto.Changeset.t()
  def change_attempt(%Scope{} = scope, %Attempt{} = attempt, attrs \\ %{}) do
    true = attempt.user_id == scope.user.id

    Attempt.changeset(attempt, attrs, scope)
  end

  @doc "Saves a word once per account, retaining known status when saved again."
  @spec save_word(Scope.t(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def save_word(%Scope{} = scope, attrs) do
    attrs =
      Map.merge(
        %{
          meaning: "Add your own meaning",
          category: "word",
          context: "",
          status: "learning",
          interval: 0,
          due_at: DateTime.utc_now(:second)
        },
        attrs
      )

    attrs = Map.update!(attrs, :term, &String.downcase(String.trim(&1)))

    case Repo.get_by(Entry, user_id: scope.user.id, term: attrs.term) do
      nil -> create_entry(scope, attrs)
      entry -> update_entry(scope, entry, Map.take(attrs, [:meaning, :context, :category]))
    end
  end

  @doc """
  Lists up to 200 recently updated owned words matching a jar or known status.

  Optional search matches literal text in the term, meaning, or context before
  limiting results, so older words can still be found. Auxiliary verbs share the
  verb jar and proper nouns share the noun jar.
  """
  @spec vocabulary(Scope.t(), String.t()) :: [Entry.t()]
  @spec vocabulary(Scope.t(), String.t(), String.t()) :: [Entry.t()]
  def vocabulary(scope, filter, search \\ "") do
    query = from e in Entry, where: e.user_id == ^scope.user.id, order_by: [desc: e.updated_at], limit: 200

    query =
      case filter do
        "all" -> query
        "known" -> from e in query, where: e.status == "known"
        "noun" -> from e in query, where: e.category in ["noun", "proper"]
        "verb" -> from e in query, where: e.category in ["verb", "aux"]
        category -> from e in query, where: e.category == ^category
      end

    query =
      if search == "" do
        query
      else
        pattern = "%" <> String.replace(search, ["\\", "%", "_"], &"\\#{&1}") <> "%"
        from e in query, where: ilike(e.term, ^pattern) or ilike(e.meaning, ^pattern) or ilike(e.context, ^pattern)
      end

    Repo.all(query)
  end

  @doc "Finds the next due learning card without exposing other users' records."
  @spec next_review(Scope.t()) :: Entry.t() | nil
  def next_review(scope) do
    now = DateTime.utc_now(:second)

    Repo.one(
      from e in Entry,
        where: e.user_id == ^scope.user.id and e.status != "known" and e.due_at <= ^now,
        order_by: [asc: e.due_at],
        limit: 1
    )
  end

  @doc "Schedules a rated review and records its result atomically."
  @spec rate(Scope.t(), Ecto.UUID.t(), String.t()) :: {:ok, Entry.t()} | {:error, term()}
  def rate(scope, id, rating) when rating in ["again", "hard", "good", "easy"] do
    with {:ok, {entry, attempt}} <- Repo.transact(fn -> rate_locked(scope, id, rating) end) do
      broadcast_entry(scope, {:updated, entry})
      broadcast_attempt(scope, {:created, attempt})
      {:ok, entry}
    end
  end

  defp rate_locked(scope, id, rating) do
    seconds = %{"again" => 60, "hard" => 480, "good" => 86_400, "easy" => 345_600}
    entry = Repo.one!(from e in Entry, where: e.id == ^id and e.user_id == ^scope.user.id, lock: "FOR UPDATE")
    interval = if rating in ["good", "easy"], do: max(seconds[rating], entry.interval * 2), else: seconds[rating]
    changes = %{interval: interval, due_at: DateTime.shift(DateTime.utc_now(:second), second: interval)}
    attempt = %{kind: "review", content: entry.term, result: %{rating: rating}, duration: 0}

    with {:ok, updated} <- entry |> Entry.changeset(changes, scope) |> Repo.update(),
         {:ok, attempt} <- %Attempt{} |> Attempt.changeset(attempt, scope) |> Repo.insert() do
      {:ok, {updated, attempt}}
    end
  end

  @doc "Returns actual account activity, vocabulary totals, and recent practice history."
  @spec progress(Scope.t()) :: map()
  def progress(scope) do
    entries = from e in Entry, where: e.user_id == ^scope.user.id
    attempts = from a in Attempt, where: a.user_id == ^scope.user.id
    today = Date.utc_today()
    since = today |> Date.add(-34) |> DateTime.new!(~T[00:00:00])

    activity =
      from(a in attempts,
        where: a.inserted_at >= ^since,
        group_by: fragment("date(?)", a.inserted_at),
        select: {fragment("date(?)", a.inserted_at), count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    days =
      Enum.map(34..0//-1, fn offset ->
        date = Date.add(today, -offset)
        %{date: date, count: Map.get(activity, date, 0)}
      end)

    weekly_counts =
      from(e in entries,
        where: e.status == "known",
        group_by: fragment("date_trunc('week', ?)", e.inserted_at),
        select: {fragment("date_trunc('week', ?)", e.inserted_at), count(e.id)}
      )
      |> Repo.all()
      |> Map.new(fn {date, count} -> {NaiveDateTime.to_date(date), count} end)

    monday = Date.beginning_of_week(today)

    weekly_known =
      Enum.map(7..0//-1, fn offset ->
        date = Date.add(monday, -7 * offset)
        %{date: date, count: Map.get(weekly_counts, date, 0)}
      end)

    errors =
      Repo.all(
        from e in entries,
          where: e.category == "error",
          order_by: [desc: e.updated_at],
          limit: 5,
          select: %{id: e.id, term: e.term, meaning: e.meaning, status: e.status}
      )

    skills = Repo.all(from a in attempts, group_by: a.kind, select: {a.kind, sum(a.duration)})
    streak_start = if Map.has_key?(activity, today), do: today, else: Date.add(today, -1)

    streak =
      0..34 |> Enum.take_while(fn offset -> Map.has_key?(activity, Date.add(streak_start, -offset)) end) |> length()

    %{
      weekly_known: weekly_known,
      errors: errors,
      total: Repo.aggregate(entries, :count),
      known: Repo.aggregate(from(e in entries, where: e.status == "known"), :count),
      due:
        Repo.aggregate(from(e in entries, where: e.status != "known" and e.due_at <= ^DateTime.utc_now(:second)), :count),
      attempts: Repo.aggregate(attempts, :count),
      days: days,
      skills: skills,
      streak: streak,
      seconds: Enum.reduce(skills, 0, fn {_, seconds}, acc -> acc + (seconds || 0) end)
    }
  end

  @doc "Returns the most recent private practice attempts."
  @spec recent_attempts(Scope.t()) :: [Attempt.t()]
  def recent_attempts(scope),
    do: Repo.all(from a in Attempt, where: a.user_id == ^scope.user.id, order_by: [desc: a.inserted_at], limit: 50)
end
