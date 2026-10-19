defmodule LeitorWeb.SharedPageLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Accounts
  alias Leitor.AI
  alias Leitor.Language
  alias Leitor.Language.AnswerStream
  alias Leitor.PageDocument
  alias Leitor.Pages
  alias Leitor.Pages.Mark
  alias Leitor.Sharing
  alias LeitorWeb.ReaderComponents
  alias LeitorWeb.ReadingPreferences

  @impl true
  def mount(%{"token" => token}, session, socket) do
    preferences = if connected?(socket), do: get_connect_params(socket)["reading_preferences"] || %{}, else: %{}
    preferences = if is_map(preferences), do: preferences, else: %{}

    socket =
      socket
      |> assign(
        token: token,
        visitor_id: session["visitor_id"],
        access: nil,
        page_title: gettext("Shared page"),
        document: PageDocument.prepare(""),
        version: "",
        panel: "shared",
        panel_open: true,
        comments_page: 1,
        more_comments: false,
        comment_form: to_form(%{"author_name" => "", "body" => ""}, as: "comment"),
        reply_id: nil,
        comment_anchor: nil,
        selection: nil,
        selection_anchor: nil,
        selection_mode: "actions",
        editing: false,
        busy: false,
        pending: nil,
        lease_id: nil,
        ai_preview: "",
        ai_raw: "",
        error: nil,
        active_mark_id: nil,
        marks_json: "[]",
        personal_marks: [],
        guest_drafts: [],
        import_available: false,
        editing_highlight_id: nil,
        editing_highlight_color: nil,
        marker_color: "yellow",
        note_form: to_form(%{"body" => ""}, as: "note"),
        question_form: to_form(%{"question" => ""}, as: "question"),
        pot_form: to_form(%{"meaning" => "", "category" => "word"}, as: "pot"),
        face: if(preferences["face"] in ~w(serif book sans legible), do: preferences["face"], else: "serif"),
        font_size: if(preferences["size"] in 15..28, do: preferences["size"], else: 20),
        show_numbers: preferences["numbers"] == true,
        appearance_tab: "look",
        appearance: Map.put(ReadingPreferences.normalize(preferences), "focus", false)
      )
      |> stream(:comments, [])
      |> stream(:personal, [])

    socket = load(socket)
    if connected?(socket) and socket.assigns.access, do: Sharing.subscribe(socket.assigns.access)
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mark = Enum.find(socket.assigns.personal_marks, &(&1.id == params["mark"]))
    location = mark && PageDocument.locate(socket.assigns.document, mark)

    socket =
      if location do
        socket
        |> assign(panel: "personal", panel_open: true, active_mark_id: mark.id)
        |> refresh_personal()
        |> push_event("page-jump", %{id: mark.id})
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select", anchor, %{assigns: %{access: nil}} = socket),
    do: {:noreply, assign(socket, selection: nil, selection_anchor: anchor)}

  def handle_event("select", anchor, socket) do
    case PageDocument.selection(socket.assigns.document, anchor) do
      {:ok, selection} ->
        mark =
          Enum.find(
            socket.assigns.personal_marks,
            &(&1.id == anchor["highlight_id"] and &1.kind == "highlight" and
                PageDocument.locate(socket.assigns.document, &1) == selection)
          )

        {:noreply,
         assign(socket,
           selection: selection,
           selection_anchor: anchor,
           selection_mode: "actions",
           editing_highlight_id: mark && mark.id,
           editing_highlight_color: mark && mark.color,
           error: nil
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("close-selection", params, socket),
    do:
      {:noreply,
       socket
       |> assign(selection: nil, editing_highlight_id: nil)
       |> push_event("page-clear-selection", %{version: params["version"]})}

  def handle_event("selection-mode", %{"mode" => "comment"}, socket) do
    {:noreply,
     socket
     |> assign(
       panel: "shared",
       panel_open: true,
       comment_anchor: socket.assigns.selection_anchor,
       reply_id: nil,
       selection: nil
     )
     |> push_event("shared-comment-focus", %{})}
  end

  def handle_event("selection-mode", %{"mode" => mode}, socket) when mode in ~w(actions note ask pot),
    do: {:noreply, assign(socket, selection_mode: mode)}

  def handle_event("panel", %{"panel" => panel}, socket) when panel in ~w(shared personal),
    do: {:noreply, assign(socket, panel: panel, panel_open: true)}

  def handle_event("notebook", _, socket), do: {:noreply, assign(socket, panel_open: !socket.assigns.panel_open)}
  def handle_event("shortcuts", _, socket), do: {:noreply, socket}

  def handle_event("comment", %{"comment" => attrs}, socket) do
    attrs = Map.merge(attrs, %{"anchor" => socket.assigns.comment_anchor, "parent_id" => socket.assigns.reply_id})

    case Sharing.comment(socket.assigns.current_scope, socket.assigns.token, socket.assigns.visitor_id, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           comment_form: to_form(%{"author_name" => attrs["author_name"], "body" => ""}, as: "comment"),
           reply_id: nil,
           comment_anchor: nil,
           error: nil
         )
         |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, comment_form: to_form(changeset, as: "comment", action: :insert))}

      {:error, reason} ->
        {:noreply, fail(socket, reason)}
    end
  end

  def handle_event("reply", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(panel: "shared", panel_open: true, reply_id: id, comment_anchor: nil)
     |> push_event("shared-comment-focus", %{})}
  end

  def handle_event("cancel-comment", _, socket), do: {:noreply, assign(socket, reply_id: nil, comment_anchor: nil)}

  def handle_event("remove-comment", %{"id" => id}, socket) do
    case Sharing.remove_comment(socket.assigns.current_scope, socket.assigns.token, socket.assigns.visitor_id, id) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, reason} -> {:noreply, fail(socket, reason)}
    end
  end

  def handle_event("comment-page", %{"direction" => direction}, socket) do
    page = max(1, socket.assigns.comments_page + if(direction == "next", do: 1, else: -1))
    {:noreply, socket |> assign(comments_page: page) |> load()}
  end

  def handle_event("jump-comment", %{"id" => id}, socket) do
    with {:ok, %{entries: entries}} <-
           Sharing.comments(socket.assigns.current_scope, socket.assigns.token, socket.assigns.comments_page),
         comment when not is_nil(comment) <- Enum.find(entries, &(&1.id == id)),
         location when not is_nil(location) <- PageDocument.locate(socket.assigns.document, comment) do
      {:noreply, push_event(socket, "shared-jump", %{block: location.block_index})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("highlight", %{"color" => color}, socket) when color in ~w(yellow green blue rose) do
    attrs = %{kind: "highlight", color: color}
    socket = socket |> assign(marker_color: color) |> push_event("reading-preference", %{key: "marker", value: color})

    if socket.assigns.editing_highlight_id,
      do: update_mark(socket, socket.assigns.editing_highlight_id, attrs),
      else: keep_mark(socket, attrs)
  end

  def handle_event("note", %{"note" => %{"body" => body}}, socket), do: keep_mark(socket, %{kind: "note", body: body})

  def handle_event("activate-mark", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.personal_marks, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(panel: "personal", panel_open: true, active_mark_id: id, selection: nil)
       |> refresh_personal()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("collapse-mark", _, socket),
    do: {:noreply, socket |> assign(active_mark_id: nil) |> refresh_personal()}

  def handle_event("jump-mark", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.personal_marks, &(&1.id == id)) do
      {:noreply, push_event(socket, "page-jump", %{id: id})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("stop-help", _, socket) do
    socket = if socket.assigns.busy, do: cancel_async(socket, :shared_help), else: socket
    AI.finish(socket.assigns.current_scope, socket.assigns.lease_id, :cancelled)
    {:noreply, assign(socket, busy: false, pending: nil, lease_id: nil, ai_raw: "", ai_preview: "")}
  end

  def handle_event("remove-mark", %{"id" => id}, socket) do
    socket =
      if is_nil(socket.assigns.current_scope) do
        assign(socket, guest_drafts: Enum.reject(socket.assigns.guest_drafts, &(&1["id"] == id)))
      else
        case Enum.find(socket.assigns.personal_marks, &(&1.id == id)) do
          nil -> :ok
          _ -> Pages.delete_mark(socket.assigns.current_scope, id)
        end

        socket
      end

    {:noreply, socket |> assign(selection: nil, editing_highlight_id: nil) |> refresh_personal() |> persist_guest()}
  end

  def handle_event("guest-drafts-found", _, socket),
    do: {:noreply, assign(socket, import_available: !is_nil(socket.assigns.current_scope))}

  def handle_event("request-guest-import", _, socket), do: {:noreply, push_event(socket, "shared-request-drafts", %{})}

  def handle_event("import-guest-drafts", %{"drafts" => drafts}, %{assigns: %{current_scope: scope}} = socket)
      when not is_nil(scope) do
    case Sharing.import_drafts(scope, socket.assigns.token, drafts) do
      {:ok, _} ->
        {:noreply,
         socket |> assign(import_available: false) |> refresh_personal() |> push_event("shared-drafts", %{drafts: []})}

      {:error, reason} ->
        {:noreply, fail(socket, reason)}
    end
  end

  def handle_event("restore-guest-drafts", %{"drafts" => drafts}, %{assigns: %{current_scope: nil}} = socket)
      when is_list(drafts) do
    valid = drafts |> Enum.take(100) |> Enum.filter(&(guest_mark(socket.assigns.document, &1) != nil))
    {:noreply, socket |> assign(guest_drafts: valid) |> refresh_personal()}
  end

  def handle_event("restore-guest-drafts", _, socket), do: {:noreply, socket}

  def handle_event("save-pot", %{"pot" => attrs}, %{assigns: %{current_scope: scope}} = socket) when not is_nil(scope) do
    if socket.assigns.selection && match?({:ok, _}, Sharing.resolve(scope, socket.assigns.token)) do
      case Leitor.Learning.save_word(scope, %{
             term: socket.assigns.selection.quote,
             meaning: attrs["meaning"],
             category: attrs["category"],
             context: socket.assigns.selection.quote,
             status: "learning"
           }) do
        {:ok, _} -> {:noreply, socket |> assign(selection: nil) |> put_flash(:info, gettext("Saved to your word jars."))}
        {:error, _} -> {:noreply, assign(socket, error: gettext("Add a meaning and choose a word jar."))}
      end
    else
      {:noreply, fail(socket, :unavailable)}
    end
  end

  def handle_event("save-pot", _, socket), do: {:noreply, sign_in_hint(socket)}

  def handle_event("help", %{"action" => action} = params, socket)
      when action in ~w(define explain simplify ask dictionary) do
    scope = socket.assigns.current_scope
    question = String.trim(get_in(params, ["question", "question"]) || "")

    cond do
      is_nil(scope) ->
        {:noreply, sign_in_hint(socket)}

      socket.assigns.busy or is_nil(socket.assigns.selection) ->
        {:noreply, socket}

      String.length(question) > 500 or (action == "ask" and question == "") ->
        {:noreply, assign(socket, error: gettext("Ask a question up to 500 characters."))}

      true ->
        start_ai(socket, action, question)
    end
  end

  def handle_event("reading-option", %{"key" => key, "value" => value}, socket) do
    case ReadingPreferences.change(socket.assigns.appearance, key, value) do
      {:ok, appearance} ->
        {:noreply,
         socket
         |> assign(appearance: appearance)
         |> push_event("reading-preference", %{key: key, value: Map.fetch!(appearance, key)})}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("reading-face", %{"face" => face}, socket) when face in ~w(serif book sans legible),
    do: {:noreply, socket |> assign(face: face) |> push_event("reading-preference", %{key: "face", value: face})}

  def handle_event("reading-size", %{"size" => size}, socket)
      when size in ~w(15 16 17 18 19 20 21 22 23 24 25 26 27 28) do
    {:noreply,
     socket
     |> assign(font_size: String.to_integer(size))
     |> push_event("reading-preference", %{key: "size", value: String.to_integer(size)})}
  end

  def handle_event("reading-numbers", _, socket),
    do:
      {:noreply,
       socket
       |> assign(show_numbers: !socket.assigns.show_numbers)
       |> push_event("reading-preference", %{key: "numbers", value: !socket.assigns.show_numbers})}

  def handle_event("appearance-tab", %{"tab" => tab}, socket) when tab in ~w(look text),
    do: {:noreply, assign(socket, appearance_tab: tab)}

  def handle_event("reading-text-reset", _, socket) do
    {:noreply,
     socket
     |> assign(face: "serif", font_size: 20, appearance: ReadingPreferences.reset_text(socket.assigns.appearance))
     |> push_event(
       "reading-text-preferences-reset",
       Map.take(ReadingPreferences.defaults(), ~w(leading width align paras))
     )}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:share_changed, socket), do: {:noreply, load(socket)}

  def handle_info({:shared_ai_fragment, fragment}, %{assigns: %{busy: true}} = socket) do
    raw = String.slice(socket.assigns.ai_raw <> fragment, 0, 32_000)
    {:noreply, assign(socket, ai_raw: raw, ai_preview: AnswerStream.preview(raw))}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:shared_help, _result, %{assigns: %{pending: nil}} = socket), do: {:noreply, socket}

  def handle_async(:shared_help, {:ok, {:ok, data}}, %{assigns: %{pending: pending}} = socket) when not is_nil(pending) do
    result =
      Sharing.create_mark(socket.assigns.current_scope, socket.assigns.token, pending.anchor, %{
        kind: if(pending.action in ~w(define dictionary), do: "definition", else: "answer"),
        body: data["answer"],
        meaning: data["meaning"],
        category: data["category"],
        question: if(pending.question == "", do: String.capitalize(pending.action), else: pending.question)
      })

    AI.finish(socket.assigns.current_scope, socket.assigns.lease_id)
    socket = assign(socket, busy: false, pending: nil, lease_id: nil, ai_preview: "", error: nil)

    case result do
      {:ok, mark} -> {:noreply, socket |> assign(active_mark_id: mark.id) |> refresh_personal()}
      {:error, reason} -> {:noreply, fail(socket, reason)}
    end
  end

  def handle_async(:shared_help, _, socket) do
    AI.finish(socket.assigns.current_scope, socket.assigns.lease_id, :failed)

    {:noreply,
     assign(socket,
       busy: false,
       pending: nil,
       lease_id: nil,
       error: gettext("The response could not be completed. Try again.")
     )}
  end

  @impl true
  def terminate(_, socket) do
    AI.finish(socket.assigns.current_scope, socket.assigns.lease_id, :cancelled)
    :ok
  end

  defp load(socket) do
    with {:ok, access} <- Sharing.resolve(socket.assigns.current_scope, socket.assigns.token),
         {:ok, comments} <-
           Sharing.comments(socket.assigns.current_scope, socket.assigns.token, socket.assigns.comments_page) do
      version = Base.encode16(:crypto.hash(:sha256, access.page.body), case: :lower)

      socket =
        if version == socket.assigns.version,
          do: socket,
          else: reset_source(socket)

      socket
      |> assign(
        access: access,
        page_title: access.page.title,
        document: PageDocument.prepare(access.page.body),
        version: version,
        more_comments: comments.more?
      )
      |> stream(:comments, comments.entries, reset: true)
      |> refresh_personal()
    else
      {:error, :unavailable} ->
        socket = if socket.assigns.busy, do: cancel_async(socket, :shared_help), else: socket
        AI.finish(socket.assigns.current_scope, socket.assigns.lease_id, :cancelled)

        socket
        |> assign(
          access: nil,
          document: PageDocument.prepare(""),
          selection: nil,
          comment_anchor: nil,
          personal_marks: [],
          marks_json: "[]",
          busy: false,
          pending: nil,
          lease_id: nil
        )
        |> stream(:comments, [], reset: true)
        |> stream(:personal, [], reset: true)
    end
  end

  defp start_ai(socket, action, question) do
    scope = socket.assigns.current_scope

    with {:ok, _} <- Sharing.resolve(scope, socket.assigns.token), {:ok, client} <- AI.prepare(scope, :read) do
      selection = socket.assigns.selection
      blocks = socket.assigns.document.blocks
      anchor = socket.assigns.selection_anchor
      options = AI.execution_options(scope, client)
      preferences = Accounts.get_preferences(scope)
      owner = self()

      socket =
        assign(socket,
          busy: true,
          pending: %{
            anchor: anchor,
            action: action,
            quote: selection.quote,
            question: question,
            block_index: selection.block_index,
            mark_id: nil
          },
          lease_id: client.lease_id,
          ai_preview: "",
          ai_raw: "",
          selection: nil,
          panel: "personal",
          panel_open: true,
          error: nil
        )

      {:noreply,
       start_async(socket, :shared_help, fn ->
         if action == "dictionary" do
           case dictionary_answer(blocks, selection, options) do
             {:ok, card} ->
               {:ok,
                %{
                  "answer" => Leitor.Dictionary.markdown(card),
                  "meaning" => card["meaning"],
                  "category" => Leitor.Dictionary.jar_category(card)
                }}

             error ->
               error
           end
         else
           Language.page_help(
             action,
             selection.quote,
             blocks,
             question,
             [],
             fn fragment -> send(owner, {:shared_ai_fragment, fragment}) end,
             preferences,
             options
           )
         end
       end)}
    else
      {:error, reason} -> {:noreply, fail(socket, reason)}
    end
  end

  defp dictionary_answer(blocks, selection, options) do
    case Leitor.Dictionary.request(blocks, selection.block_index, selection.quote, nil) do
      {:error, _} = error -> error
      request -> Leitor.Dictionary.lookup(request, options)
    end
  end

  defp reset_source(socket) do
    if socket.assigns.busy do
      AI.finish(socket.assigns.current_scope, socket.assigns.lease_id, :cancelled)
    end

    socket = if socket.assigns.busy, do: cancel_async(socket, :shared_help), else: socket

    assign(socket,
      selection: nil,
      comment_anchor: nil,
      reply_id: nil,
      guest_drafts: [],
      busy: false,
      pending: nil,
      lease_id: nil
    )
  end

  defp refresh_personal(%{assigns: %{access: nil}} = socket), do: socket

  defp refresh_personal(socket) do
    marks = personal_marks(socket.assigns)

    mapped =
      Enum.map(marks, fn mark ->
        at = PageDocument.locate(socket.assigns.document, mark)

        %{
          id: mark.id,
          kind: mark.kind,
          color: mark.color,
          quote: mark.quote,
          active: mark.id == socket.assigns.active_mark_id,
          from: at && at.from_offset,
          to: at && at.to_offset,
          block: at && at.block_index
        }
      end)

    socket
    |> assign(personal_marks: marks, marks_json: Jason.encode!(mapped))
    |> stream(:personal, marks, reset: true)
    |> push_event("page-marks", %{marks: mapped})
  end

  defp personal_marks(%{current_scope: nil} = assigns) do
    assigns.guest_drafts |> Enum.map(&guest_mark(assigns.document, &1)) |> Enum.reject(&is_nil/1)
  end

  defp personal_marks(assigns), do: Pages.list_marks(assigns.current_scope, assigns.access.page.id)

  defp keep_mark(%{assigns: %{selection: nil}} = socket, _attrs), do: {:noreply, socket}

  defp keep_mark(socket, attrs) do
    if socket.assigns.current_scope do
      case Sharing.create_mark(socket.assigns.current_scope, socket.assigns.token, socket.assigns.selection_anchor, attrs) do
        {:ok, mark} ->
          {:noreply,
           socket
           |> assign(selection: nil, panel: "personal", panel_open: true, active_mark_id: mark.id)
           |> refresh_personal()}

        {:error, reason} ->
          {:noreply, fail(socket, reason)}
      end
    else
      draft = %{
        "id" => "guest-" <> Ecto.UUID.generate(),
        "anchor" => socket.assigns.selection_anchor,
        "attrs" => Map.new(attrs, fn {key, value} -> {Atom.to_string(key), value} end)
      }

      if length(socket.assigns.guest_drafts) < 100 and guest_mark(socket.assigns.document, draft) do
        {:noreply,
         socket
         |> assign(
           selection: nil,
           guest_drafts: socket.assigns.guest_drafts ++ [draft],
           active_mark_id: draft["id"],
           panel: "personal",
           panel_open: true
         )
         |> refresh_personal()
         |> persist_guest()}
      else
        {:noreply, assign(socket, error: gettext("Keep a shorter note or remove an older guest note."))}
      end
    end
  end

  defp update_mark(socket, id, attrs) do
    mark = Enum.find(socket.assigns.personal_marks, &(&1.id == id))

    if mark && match?({:ok, _}, Sharing.resolve(socket.assigns.current_scope, socket.assigns.token)) do
      socket =
        if socket.assigns.current_scope do
          {:ok, _} = Pages.update_mark(socket.assigns.current_scope, id, attrs)
          socket
        else
          drafts = Enum.map(socket.assigns.guest_drafts, &update_guest(&1, id, attrs))

          assign(socket, guest_drafts: drafts)
        end

      {:noreply, socket |> assign(selection: nil, editing_highlight_id: nil) |> refresh_personal() |> persist_guest()}
    else
      {:noreply, socket}
    end
  end

  defp update_guest(%{"id" => id} = draft, id, attrs) do
    values = Map.new(attrs, fn {key, value} -> {Atom.to_string(key), value} end)
    Map.update!(draft, "attrs", &Map.merge(&1, values))
  end

  defp update_guest(draft, _id, _attrs), do: draft

  defp guest_mark(document, %{"id" => "guest-" <> id, "anchor" => anchor, "attrs" => attrs}) when is_map(attrs) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         true <- attrs["kind"] in ~w(highlight note),
         {:ok, selection} <- PageDocument.selection(document, anchor),
         {:ok, mark} <-
           %Mark{id: "guest-" <> id}
           |> struct!(selection)
           |> Mark.changeset(attrs)
           |> Ecto.Changeset.apply_action(:insert) do
      mark
    else
      _ -> nil
    end
  end

  defp guest_mark(_document, _draft), do: nil

  defp persist_guest(%{assigns: %{current_scope: nil}} = socket),
    do: push_event(socket, "shared-drafts", %{drafts: socket.assigns.guest_drafts})

  defp persist_guest(socket), do: socket

  defp sign_in_hint(socket),
    do: assign(socket, error: gettext("Sign in to use AI and save words. Your account uses its own allowance."))

  defp fail(socket, :unavailable), do: load(socket)
  defp fail(socket, :forbidden), do: assign(socket, error: gettext("You do not have permission to comment on this page."))

  defp fail(socket, :invalid_selection),
    do: assign(socket, error: gettext("Select a passage from the page before commenting."))

  defp fail(socket, :rate_limited),
    do: assign(socket, error: gettext("Please wait a minute before adding another comment."))

  defp fail(socket, :quota_exceeded), do: assign(socket, error: gettext("Your daily AI allowance has been reached."))
  defp fail(socket, _reason), do: assign(socket, error: gettext("This action could not be completed. Try again."))
end
