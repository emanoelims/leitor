defmodule Leitor.Sharing do
  @moduledoc "Page-level link and email permissions, shared comments, and reader-owned annotations. Every operation rechecks the current sharing policy."
  import Ecto.Query

  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Artifact
  alias Leitor.Library.Text
  alias Leitor.PageDocument
  alias Leitor.Pages
  alias Leitor.Pages.Mark
  alias Leitor.Repo
  alias Leitor.Sharing.Collaborator
  alias Leitor.Sharing.Comment
  alias Leitor.Sharing.Share

  @typedoc "Current access to one source page. Only the owner can manage sharing; comments never grant editing."
  @type access :: %{share: Share.t(), page: Text.t(), role: String.t()}
  @typedoc "Expected authorization and bounded-input failures."
  @type error :: :unavailable | :forbidden | :invalid_selection | :rate_limited | Ecto.Changeset.t()

  @doc "Gets or creates the owner's initially restricted sharing policy. Does not publish the page."
  @spec ensure(Scope.t(), Ecto.UUID.t()) :: Share.t()
  def ensure(scope, page_id) do
    page = Pages.get_page!(scope, page_id)
    Repo.insert!(%Share{text_id: page.id, token: token()}, on_conflict: :nothing, conflict_target: :text_id)
    Repo.get_by!(Share, text_id: page.id)
  end

  @doc "Lists at most 100 explicit collaborators for an owned page."
  @spec collaborators(Scope.t(), Ecto.UUID.t()) :: [Collaborator.t()]
  def collaborators(scope, page_id) do
    share = ensure(scope, page_id)
    Repo.all(from c in Collaborator, where: c.share_id == ^share.id, order_by: c.email, limit: 100)
  end

  @doc "Changes general link access to disabled, view or comment; broadcasts revocation to open readers."
  @spec set_link(Scope.t(), Ecto.UUID.t(), map()) :: {:ok, Share.t()} | {:error, Ecto.Changeset.t()}
  def set_link(scope, page_id, attrs) do
    share = ensure(scope, page_id)

    with {:ok, share} <- share |> Share.changeset(attrs) |> Repo.update() do
      changed(share.id)
      {:ok, share}
    end
  end

  @doc "Rotates the bearer token, invalidating all older URLs while preserving explicit collaborator permissions."
  @spec rotate(Scope.t(), Ecto.UUID.t()) :: Share.t()
  def rotate(scope, page_id) do
    share = ensure(scope, page_id)
    share = share |> Ecto.Changeset.change(token: token()) |> Repo.update!()
    changed(share.id)
    share
  end

  @doc "Grants or updates view/comment access for a normalized email. The email must be confirmed before it grants access. This function does not send email."
  @spec invite(Scope.t(), Ecto.UUID.t(), map()) ::
          {:ok, Collaborator.t()} | {:error, Ecto.Changeset.t() | :rate_limited}
  def invite(scope, page_id, attrs) do
    share = ensure(scope, page_id)
    changeset = Collaborator.changeset(%Collaborator{share_id: share.id}, attrs)

    result =
      Repo.transact(fn ->
        Repo.one!(from s in Share, where: s.id == ^share.id, lock: "FOR UPDATE")
        email = Ecto.Changeset.get_field(changeset, :email)
        existing = email && Repo.exists?(from c in Collaborator, where: c.share_id == ^share.id and c.email == ^email)

        if not existing and Repo.aggregate(from(c in Collaborator, where: c.share_id == ^share.id), :count) >= 100 do
          {:error, :rate_limited}
        else
          Repo.insert(changeset,
            on_conflict: {:replace, [:role, :updated_at]},
            conflict_target: [:share_id, :email],
            returning: true
          )
        end
      end)

    notify(result, share.token)
  end

  @doc "Removes only an explicit collaborator of the caller's own page. General link access still applies."
  @spec remove_collaborator(Scope.t(), Ecto.UUID.t(), term()) :: :ok
  def remove_collaborator(scope, page_id, id) do
    share = ensure(scope, page_id)

    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.delete_all(from c in Collaborator, where: c.share_id == ^share.id and c.id == ^id)
      :error -> :ok
    end

    changed(share.id)
    :ok
  end

  @doc "Resolves a current link for an optional authenticated scope. Restricted invitations match confirmed account emails only. Missing or revoked links return unavailable."
  @spec resolve(Scope.t() | nil, term()) :: {:ok, access()} | {:error, :unavailable}
  def resolve(scope, token) when is_binary(token) and byte_size(token) == 43 do
    with %Share{} = share <- Repo.get_by(Share, token: token),
         %Text{} = page <- Repo.get(Text, share.text_id),
         role when role != nil <- role(scope, share, page) do
      {:ok, %{share: share, page: page, role: role}}
    else
      _ -> {:error, :unavailable}
    end
  end

  def resolve(_scope, _token), do: {:error, :unavailable}

  defp role(%Scope{user: %{id: id}}, _share, %{user_id: id}), do: "owner"

  defp role(%Scope{user: %{email: email, confirmed_at: confirmed}}, share, _page) when not is_nil(confirmed) do
    explicit = Repo.one(from c in Collaborator, where: c.share_id == ^share.id and c.email == ^email, select: c.role)
    if explicit == "comment" or share.link_role == "comment", do: "comment", else: explicit || link_role(share)
  end

  defp role(_scope, share, _page), do: link_role(share)
  defp link_role(%{link_role: "disabled"}), do: nil
  defp link_role(%{link_role: role}), do: role

  @doc "Invalidates shared readers after an owner changes the source text; broadcasts only the share topic."
  @spec page_changed(Ecto.UUID.t()) :: :ok
  def page_changed(page_id) do
    case Repo.get_by(Share, text_id: page_id) do
      nil -> :ok
      share -> changed(share.id)
    end
  end

  @doc "Returns accessible sharing tokens for the supplied notebook sources; private invitations require confirmed email."
  @spec links_for(Scope.t(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => String.t()}
  def links_for(%Scope{user: user}, ids) do
    email = if user.confirmed_at, do: user.email, else: ""

    from(s in Share,
      left_join: c in Collaborator,
      on: c.share_id == s.id and c.email == ^email,
      where: s.text_id in ^ids and (s.link_role != "disabled" or not is_nil(c.id)),
      select: {s.text_id, s.token}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Subscribes an authorized reader to invalidations and comment changes. Broadcasts contain no page text, comments, emails or tokens."
  @spec subscribe(access()) :: :ok | {:error, term()}
  def subscribe(%{share: share}), do: Phoenix.PubSub.subscribe(Leitor.PubSub, "page-share:#{share.id}")

  @doc "Returns a bounded page of shared comments, oldest first within the selected 50-comment page. Never returns private annotations."
  @spec comments(Scope.t() | nil, String.t(), pos_integer()) ::
          {:ok, %{entries: [Comment.t()], more?: boolean()}} | {:error, :unavailable}
  def comments(scope, token, page \\ 1) when is_integer(page) and page > 0 do
    with {:ok, access} <- resolve(scope, token) do
      entries =
        Repo.all(
          from c in Comment,
            where: c.share_id == ^access.share.id,
            order_by: [asc: c.inserted_at, asc: c.id],
            limit: 51,
            offset: ^((page - 1) * 50)
        )

      {:ok, %{entries: Enum.take(entries, 50), more?: length(entries) > 50}}
    end
  end

  @doc "Creates an attributed comment or reply after locking and rechecking access. Quotes come from the stored page or a same-page public parent. Guests have a signed browser identity, not an authenticated account. At most six comments per actor per minute and 1000 per page are accepted."
  @spec comment(Scope.t() | nil, String.t(), Ecto.UUID.t(), map()) :: {:ok, Comment.t()} | {:error, error()}
  def comment(scope, token, visitor_id, attrs) do
    write(scope, token, fn access ->
      with :ok <- can_comment(access),
           :ok <- comment_capacity(scope, access, visitor_id),
           {:ok, selection, parent_id} <- comment_selection(access, attrs) do
        comment =
          struct!(
            Comment,
            Map.merge(selection, %{
              share_id: access.share.id,
              user_id: user_id(scope),
              visitor_id: visitor_id,
              parent_id: parent_id
            })
          )

        comment |> Comment.changeset(attrs) |> Repo.insert()
      end
    end)
  end

  defp can_comment(%{role: role}) when role in ~w(owner comment), do: :ok
  defp can_comment(_access), do: {:error, :forbidden}

  defp comment_capacity(scope, access, visitor_id) do
    since = DateTime.shift(DateTime.utc_now(:second), minute: -1)
    id = user_id(scope)

    actor =
      if id, do: dynamic([c], c.user_id == ^id), else: dynamic([c], is_nil(c.user_id) and c.visitor_id == ^visitor_id)

    recent =
      Repo.aggregate(
        from(c in Comment, where: c.share_id == ^access.share.id and c.inserted_at >= ^since, where: ^actor),
        :count
      )

    total = Repo.aggregate(from(c in Comment, where: c.share_id == ^access.share.id), :count)
    if recent < 6 and total < 1000, do: :ok, else: {:error, :rate_limited}
  end

  defp comment_selection(access, %{"parent_id" => id}) when is_binary(id) and id != "" do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Comment{deleted_at: nil} = parent <-
           Repo.one(from c in Comment, where: c.id == ^id and c.share_id == ^access.share.id) do
      {:ok, Map.take(parent, [:quote, :from_offset, :to_offset, :block_index]), parent.id}
    else
      _ -> {:error, :invalid_selection}
    end
  end

  defp comment_selection(access, %{"anchor" => anchor}) do
    with {:ok, selection} <- PageDocument.selection(PageDocument.prepare(access.page.body), anchor),
         do: {:ok, selection, nil}
  end

  defp comment_selection(_access, _attrs), do: {:error, :invalid_selection}

  @doc "Removes comment content without erasing other people's replies. Only its author or the page owner can remove it; access is checked again."
  @spec remove_comment(Scope.t() | nil, String.t(), Ecto.UUID.t(), term()) :: {:ok, Comment.t()} | {:error, error()}
  def remove_comment(scope, token, visitor_id, id) do
    write(scope, token, fn access ->
      with {:ok, id} <- Ecto.UUID.cast(id),
           %Comment{} = comment <- Repo.one(from c in Comment, where: c.id == ^id and c.share_id == ^access.share.id),
           true <- access.role == "owner" or author?(scope, visitor_id, comment) do
        comment |> Ecto.Changeset.change(body: "", deleted_at: DateTime.utc_now(:second)) |> Repo.update()
      else
        _ -> {:error, :forbidden}
      end
    end)
  end

  @doc "Checks whether a comment belongs to this authenticated account or this anonymous browser. A logged-in account never inherits a guest identity."
  @spec author?(Scope.t() | nil, Ecto.UUID.t(), Comment.t()) :: boolean()
  def author?(%Scope{user: %{id: id}}, _visitor_id, comment), do: comment.user_id == id
  def author?(nil, visitor_id, comment), do: is_nil(comment.user_id) and comment.visitor_id == visitor_id

  @doc "Creates a private annotation owned by the authenticated reader, independently of the source page owner. Existing notebooks can read it through annotation ownership."
  @spec create_mark(Scope.t(), String.t(), map(), map()) :: {:ok, Mark.t()} | {:error, error()}
  def create_mark(%Scope{user: %{confirmed_at: confirmed}} = scope, token, anchor, attrs) when not is_nil(confirmed) do
    write(
      scope,
      token,
      fn access ->
        with {:ok, selection} <- PageDocument.selection(PageDocument.prepare(access.page.body), anchor) do
          Mark
          |> struct!(Map.merge(selection, %{text_id: access.page.id, user_id: scope.user.id}))
          |> Mark.changeset(attrs)
          |> Repo.insert()
        end
      end,
      false
    )
  end

  @doc "Imports up to 100 validated guest drafts into the current reader's private notebook. Imports are transactional and idempotent by reader, page and draft UUID; client ownership fields are ignored."
  @spec import_drafts(Scope.t(), String.t(), [map()]) :: {:ok, non_neg_integer()} | {:error, error()}
  def import_drafts(%Scope{user: %{confirmed_at: confirmed}} = scope, token, drafts)
      when not is_nil(confirmed) and is_list(drafts) and length(drafts) <= 100 do
    write(
      scope,
      token,
      fn access -> import_all_drafts(scope, access.page, drafts) end,
      false
    )
  end

  def import_drafts(_scope, _token, _drafts), do: {:error, :invalid_selection}

  defp import_all_drafts(scope, page, drafts) do
    document = PageDocument.prepare(page.body)

    Enum.reduce_while(drafts, {:ok, 0}, fn draft, {:ok, count} ->
      case import_draft(scope, page.id, document, draft) do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        error -> {:halt, error}
      end
    end)
  end

  defp import_draft(scope, page_id, document, %{"id" => "guest-" <> key, "anchor" => anchor, "attrs" => attrs})
       when is_map(attrs) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         true <- attrs["kind"] in ~w(note highlight),
         {:ok, selection} <- PageDocument.selection(document, anchor) do
      mark = struct!(Mark, Map.merge(selection, %{user_id: scope.user.id, text_id: page_id, import_key: key}))

      mark
      |> Mark.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :text_id, :import_key])
    else
      _ -> {:error, :invalid_selection}
    end
  end

  defp import_draft(_scope, _page, _document, _draft), do: {:error, :invalid_selection}

  @doc "Fetches only the accepted figure payload explicitly embedded in an accessible page and owned by its author. Private code, evidence and unrelated artifacts are never returned."
  @spec figure(Scope.t() | nil, String.t(), term()) :: {:ok, map()} | {:error, :unavailable}
  def figure(scope, token, id) do
    with {:ok, access} <- resolve(scope, token),
         {:ok, id} <- Ecto.UUID.cast(id),
         true <- id in figure_ids(MDEx.parse_document!(access.page.body)),
         payload when not is_nil(payload) <-
           Repo.one(
             from a in Artifact,
               where: a.id == ^id and a.user_id == ^access.page.user_id and a.status == "ready",
               select: %{
                 bundle: a.bundle,
                 style: a.style,
                 digest: a.digest,
                 custom_style: fragment("?->>'css'", a.source)
               }
           ) do
      {:ok, %{payload | custom_style: payload.custom_style || ""}}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp figure_ids(%MDEx.CodeBlock{info: "leitor-figure", literal: source}) do
    case Leitor.Figures.decode(source) do
      {:ok, %{engine: "anatomy-program", artifact_id: id}} -> [id]
      _ -> []
    end
  end

  defp figure_ids(%{nodes: nodes}), do: Enum.flat_map(nodes, &figure_ids/1)
  defp figure_ids(_node), do: []

  defp write(scope, token, fun, notify? \\ true) do
    fn ->
      with %Share{} = share <- Repo.one(from s in Share, where: s.token == ^token, lock: "FOR UPDATE"),
           {:ok, access} <- resolve(scope, share.token) do
        fun.(access)
      else
        _ -> {:error, :unavailable}
      end
    end
    |> Repo.transact()
    |> then(fn result -> if notify?, do: notify(result, token), else: result end)
  end

  defp notify({:ok, value} = result, token) do
    case Repo.get_by(Share, token: token) do
      nil -> :ok
      share -> changed(share.id)
    end

    _ = value
    result
  end

  defp notify(error, _token), do: error
  defp changed(id), do: Phoenix.PubSub.broadcast(Leitor.PubSub, "page-share:#{id}", :share_changed)
  defp user_id(%Scope{user: %{id: id}}), do: id
  defp user_id(nil), do: nil
  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
end
