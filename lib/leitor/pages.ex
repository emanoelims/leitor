defmodule Leitor.Pages do
  @moduledoc "Private, freely editable Markdown pages and their source-validated annotations."
  import Ecto.Query

  alias Leitor.Accounts.Scope
  alias Leitor.Library
  alias Leitor.Library.Text
  alias Leitor.PageDocument
  alias Leitor.Pages.Mark
  alias Leitor.Pages.Reply
  alias Leitor.Repo

  @notebook_page_size 30

  @typedoc "Optional notebook filters: literal search text, annotation kind, and an owned source page ID."
  @type notebook_filters() :: %{
          optional(:search) => String.t(),
          optional(:kind) => String.t(),
          optional(:text_id) => Ecto.UUID.t() | nil
        }
  @typedoc "A source page with at least one caller-owned annotation."
  @type notebook_source() :: %{id: Ecto.UUID.t(), title: String.t()}
  @typedoc "A bounded notebook result with preloaded source titles and pagination metadata."
  @type notebook_page() :: %{
          entries: [Mark.t()],
          total: non_neg_integer(),
          page: pos_integer(),
          per_page: pos_integer()
        }

  @doc """
  Returns caller-owned annotations across pages, newest updates first, 30 at a time.

  `:search` matches literal text in quotes, answers, questions, and source titles.
  `:kind` accepts an annotation kind or `"all"`; `:text_id` is a valid UUID or `nil`.
  Filters never expand ownership. Source associations contain only ID and title.
  Positive page numbers beyond the last page are clamped to the last page.
  """
  @spec notebook(Scope.t(), notebook_filters(), pos_integer()) :: notebook_page()
  def notebook(%Scope{} = scope, filters \\ %{}, page \\ 1) when is_map(filters) and is_integer(page) and page > 0 do
    query =
      scope
      |> owned_marks()
      |> notebook_kind(Map.get(filters, :kind, "all"))
      |> notebook_source(Map.get(filters, :text_id))
      |> notebook_search(Map.get(filters, :search, ""))

    total = Repo.aggregate(query, :count)
    page = min(page, max(div(total + @notebook_page_size - 1, @notebook_page_size), 1))
    sources = from t in Text, select: [:id, :title]

    entries =
      Repo.all(
        from m in query,
          order_by: [desc: m.updated_at, desc: m.id],
          limit: @notebook_page_size,
          offset: ^((page - 1) * @notebook_page_size),
          preload: [text: ^sources]
      )

    %{entries: entries, total: total, page: page, per_page: @notebook_page_size}
  end

  @doc "Lists only the ID and title of owned pages containing annotations, ordered by title."
  @spec notebook_sources(Scope.t()) :: [notebook_source()]
  def notebook_sources(%Scope{} = scope) do
    Repo.all(
      from [_m, t] in owned_marks(scope),
        distinct: true,
        order_by: [asc: t.title, asc: t.id],
        select: %{id: t.id, title: t.title}
    )
  end

  @doc "Creates a blank or populated Markdown page owned by the caller."
  @spec create_page(Scope.t(), map()) :: {:ok, Text.t()} | {:error, Ecto.Changeset.t()}
  def create_page(%Scope{} = scope, attrs \\ %{}) do
    attrs = attrs |> Map.take(["title", "body"]) |> Map.put_new("title", "Untitled") |> Map.put_new("body", "")
    Library.create_text(scope, Map.merge(attrs, %{"source" => "page", "position" => 0}))
  end

  @doc "Fetches a caller-owned page; inaccessible pages raise `Ecto.NoResultsError`."
  @spec get_page!(Scope.t(), Ecto.UUID.t()) :: Text.t()
  def get_page!(%Scope{} = scope, id), do: Library.get_text!(scope, id)

  @doc "Updates title and Markdown without replacing the page or its annotations."
  @spec update_page(Scope.t(), Text.t(), map()) :: {:ok, Text.t()} | {:error, Ecto.Changeset.t()}
  def update_page(%Scope{} = scope, text, attrs),
    do: Library.update_text(scope, text, attrs |> Map.take(["title", "body"]) |> Map.put("source", "page"))

  @doc "Lists caller-owned annotations in reading order."
  @spec list_marks(Scope.t(), Ecto.UUID.t()) :: [Mark.t()]
  def list_marks(%Scope{} = scope, id) do
    Repo.all(
      from m in Mark,
        join: t in Text,
        on: t.id == m.text_id,
        where: t.user_id == ^scope.user.id and t.id == ^id,
        order_by: [asc: m.from_offset, asc: m.inserted_at, asc: m.id]
    )
  end

  @doc "Creates an annotation from validated block offsets, deriving the quote from stored content."
  @spec create_mark(Scope.t(), Ecto.UUID.t(), map(), map()) ::
          {:ok, Mark.t()} | {:error, :invalid_selection | Ecto.Changeset.t()}
  def create_mark(%Scope{} = scope, id, anchor, attrs) do
    text = get_page!(scope, id)

    with {:ok, selection} <- PageDocument.selection(PageDocument.prepare(text.body), anchor) do
      mark = struct!(Mark, Map.put(selection, :text_id, text.id))
      mark |> Mark.changeset(attrs) |> Repo.insert()
    end
  end

  @doc "Updates an owned annotation's content or color; inaccessible annotations raise."
  @spec update_mark(Scope.t(), Ecto.UUID.t(), map()) :: {:ok, Mark.t()} | {:error, Ecto.Changeset.t()}
  def update_mark(%Scope{} = scope, id, attrs), do: scope |> get_mark!(id) |> Mark.changeset(attrs) |> Repo.update()

  @doc "Appends a validated exchange to an owned annotation, preserving concurrent replies and limiting conversations to 20 exchanges."
  @spec append_reply(Scope.t(), Ecto.UUID.t(), map()) :: {:ok, Mark.t()} | {:error, Ecto.Changeset.t()}
  def append_reply(%Scope{} = scope, id, attrs) do
    with {:ok, reply} <- Reply.new(attrs) do
      Repo.transact(fn ->
        mark = Repo.one!(from m in owned_marks(scope), where: m.id == ^id, lock: "FOR UPDATE")

        mark
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_embed(:replies, mark.replies ++ [reply])
        |> Ecto.Changeset.validate_length(:replies, max: 20)
        |> Repo.update()
      end)
    end
  end

  @doc "Deletes an owned annotation; inaccessible annotations raise."
  @spec delete_mark(Scope.t(), Ecto.UUID.t()) :: {:ok, Mark.t()} | {:error, Ecto.Changeset.t()}
  def delete_mark(%Scope{} = scope, id), do: scope |> get_mark!(id) |> Repo.delete()

  @doc "Fetches an annotation only when its parent page belongs to the caller."
  @spec get_mark!(Scope.t(), Ecto.UUID.t()) :: Mark.t()
  def get_mark!(%Scope{} = scope, id) do
    Repo.one!(from m in owned_marks(scope), where: m.id == ^id)
  end

  defp owned_marks(scope), do: from(m in Mark, join: t in Text, on: t.id == m.text_id, where: t.user_id == ^scope.user.id)

  defp notebook_kind(query, "all"), do: query
  defp notebook_kind(query, kind), do: where(query, [m], m.kind == ^kind)
  defp notebook_source(query, nil), do: query
  defp notebook_source(query, id), do: where(query, [m], m.text_id == ^id)
  defp notebook_search(query, ""), do: query

  defp notebook_search(query, search) do
    escaped = search |> String.replace("\\", "\\\\") |> String.replace("%", "\\%") |> String.replace("_", "\\_")
    pattern = "%#{escaped}%"

    where(
      query,
      [m, t],
      ilike(m.quote, ^pattern) or ilike(m.body, ^pattern) or ilike(m.question, ^pattern) or ilike(t.title, ^pattern)
    )
  end
end
