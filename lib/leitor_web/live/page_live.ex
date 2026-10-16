defmodule LeitorWeb.PageLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Accounts
  alias Leitor.Dictionary
  alias Leitor.Language
  alias Leitor.Language.AnswerStream
  alias Leitor.Learning
  alias Leitor.PageDocument
  alias Leitor.Pages
  alias Leitor.WritingDocument
  alias LeitorWeb.ReaderComponents
  alias LeitorWeb.ReadingPreferences
  alias LeitorWeb.WritingComponents

  @impl true
  def mount(_, _, socket) do
    preferences =
      case connected?(socket) && get_connect_params(socket)["reading_preferences"] do
        preferences when is_map(preferences) -> preferences
        _ -> %{}
      end

    {:ok,
     socket
     |> assign(
       page_title: "Untitled",
       text: nil,
       editing: true,
       dirty: false,
       saved: false,
       face: if(preferences["face"] in ~w(serif book sans legible), do: preferences["face"], else: "serif"),
       font_size: if(preferences["size"] in 15..28, do: preferences["size"], else: 20),
       show_numbers: preferences["numbers"] == true,
       shortcuts_open: false,
       appearance_tab: "look",
       appearance: Map.put(ReadingPreferences.normalize(preferences), "focus", false),
       marker_color: if(preferences["marker"] in ~w(yellow green blue rose), do: preferences["marker"], else: "yellow"),
       document: PageDocument.prepare(""),
       selection: nil,
       selection_anchor: nil,
       selection_mode: "actions",
       editing_mark_id: nil,
       notebook_open: false,
       notebook_filter: "all",
       mark_count: 0,
       active_mark_id: nil,
       busy: false,
       pending: nil,
       help_stream: nil,
       generation_id: nil,
       generation_preview: %{text: "", timer: nil},
       error: nil,
       form: to_form(%{"title" => "Untitled", "body" => ""}, as: "page"),
       note_form: to_form(%{"body" => ""}, as: "note"),
       question_form: to_form(%{"question" => ""}, as: "question"),
       pot_form: to_form(%{"meaning" => "", "category" => "word"}, as: "pot"),
       marks_json: "[]",
       notebook_markdown: ""
     )
     |> stream(:margin_marks, [])
     |> stream(:notebook_marks, [])}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _, socket) do
    text = Pages.get_page!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> stop_page_help()
     |> cancel_page_generation()
     |> assign(
       text: text,
       active_mark_id: nil,
       page_title: text.title,
       editing: text.body == "",
       dirty: false,
       saved: true,
       busy: false,
       selection: nil,
       pending: nil,
       form: to_form(%{"title" => text.title, "body" => text.body}, as: "page"),
       appearance: Map.put(socket.assigns.appearance, "focus", false),
       document: PageDocument.prepare(text.body)
     )
     |> refresh_marks(params["mark"])}
  end

  def handle_params(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("draft", %{"page" => attrs}, socket),
    do: {:noreply, assign(socket, dirty: true, form: to_form(attrs, as: "page"))}

  def handle_event(
        "generate-page-text",
        %{"request_id" => id, "prompt" => prompt, "context" => context, "title" => title},
        %{assigns: %{editing: true, generation_id: nil}} = socket
      )
      when is_binary(id) and byte_size(id) <= 64 and is_binary(prompt) and is_binary(context) and is_binary(title) do
    request = %{prompt: prompt, context: String.slice(context, 0, 24_000), title: String.slice(title, 0, 180)}
    owner = self()
    preferences = Accounts.get_preferences(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(generation_id: id)
     |> start_async({:generate_page, id}, fn ->
       on_delta = fn delta -> send(owner, {:page_generation_delta, id, delta}) end
       Language.generate_page_text(request, on_delta, preferences)
     end)}
  end

  def handle_event("generate-page-text", _, socket), do: {:noreply, socket}

  def handle_event("cancel-page-generation", %{"request_id" => id}, %{assigns: %{generation_id: id}} = socket),
    do: {:noreply, cancel_page_generation(socket)}

  def handle_event("cancel-page-generation", _, socket), do: {:noreply, socket}

  def handle_event("stop-page-generation", _, %{assigns: %{generation_id: nil}} = socket), do: {:noreply, socket}

  def handle_event("stop-page-generation", _, socket) do
    id = socket.assigns.generation_id
    {:noreply, socket |> cancel_page_generation() |> push_event("page-ai-stopped", %{request_id: id})}
  end

  def handle_event("edit", _, socket), do: {:noreply, socket |> stop_page_help() |> assign(editing: true, selection: nil)}

  def handle_event("save", %{"page" => attrs}, socket) do
    result =
      if socket.assigns.text,
        do: Pages.update_page(socket.assigns.current_scope, socket.assigns.text, attrs),
        else: Pages.create_page(socket.assigns.current_scope, attrs)

    case result do
      {:ok, text} ->
        {:noreply,
         socket
         |> cancel_page_generation()
         |> push_event("page-saved", %{
           key:
             "#{socket.assigns.current_scope.user.id}:#{if socket.assigns.text, do: socket.assigns.text.id, else: "new"}"
         })
         |> assign(dirty: false, saved: true, editing: false)
         |> push_patch(to: ~p"/pages/#{text.id}")
         |> push_event("page-read-start", %{})}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset, as: "page", action: :insert),
           error: "Use a title up to 180 characters and a page up to 300,000 characters."
         )}
    end
  end

  def handle_event("select", anchor, socket) do
    case PageDocument.selection(socket.assigns.document, anchor) do
      {:ok, selection} ->
        {:noreply,
         assign(socket,
           selection: selection,
           editing_mark_id: nil,
           selection_anchor: anchor,
           selection_mode: "actions",
           error: nil,
           note_form: to_form(%{"body" => ""}, as: "note"),
           pot_form: to_form(%{"meaning" => "", "category" => "word"}, as: "pot")
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("close-selection", params, socket),
    do:
      {:noreply,
       socket
       |> assign(selection: nil, editing_mark_id: nil)
       |> push_event("page-clear-selection", %{version: params["version"]})}

  def handle_event("reading-face", %{"face" => face}, socket) when face in ~w(serif book sans legible) do
    {:noreply, socket |> assign(face: face) |> push_event("reading-preference", %{key: "face", value: face})}
  end

  def handle_event("reading-size", %{"size" => size}, socket)
      when size in ~w(15 16 17 18 19 20 21 22 23 24 25 26 27 28) do
    size = String.to_integer(size)
    {:noreply, socket |> assign(font_size: size) |> push_event("reading-preference", %{key: "size", value: size})}
  end

  def handle_event("reading-numbers", _, socket) do
    show_numbers = !socket.assigns.show_numbers

    {:noreply,
     socket
     |> assign(show_numbers: show_numbers)
     |> push_event("reading-preference", %{key: "numbers", value: show_numbers})}
  end

  def handle_event("shortcuts", _, socket), do: {:noreply, assign(socket, shortcuts_open: !socket.assigns.shortcuts_open)}

  def handle_event("appearance-tab", %{"tab" => tab}, socket) when tab in ["look", "text"],
    do: {:noreply, assign(socket, appearance_tab: tab)}

  def handle_event("reading-size", _, socket), do: {:noreply, socket}

  def handle_event("reading-text-reset", _, socket) do
    {:noreply,
     socket
     |> assign(face: "serif", font_size: 20, appearance: ReadingPreferences.reset_text(socket.assigns.appearance))
     |> push_event(
       "reading-text-preferences-reset",
       Map.take(ReadingPreferences.defaults(), ~w(leading width align paras))
     )
     |> push_event("reading-preference", %{key: "face", value: "serif"})
     |> push_event("reading-preference", %{key: "size", value: 20})}
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

  def handle_event("activate-mark", %{"id" => id}, socket) do
    mark = Pages.get_mark!(socket.assigns.current_scope, id)

    if mark.text_id == socket.assigns.text.id do
      socket =
        if mark.kind == "highlight",
          do: assign(socket, active_mark_id: nil, selection: nil, notebook_open: true, notebook_filter: "highlight"),
          else: assign(socket, active_mark_id: id, selection: nil)

      {:noreply, refresh_marks(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("collapse-mark", _, socket), do: {:noreply, socket |> assign(active_mark_id: nil) |> refresh_marks()}

  def handle_event("stop-help", _, socket) do
    {:noreply, socket |> stop_page_help() |> assign(error: nil) |> refresh_marks()}
  end

  def handle_event("follow-up", %{"id" => id, "follow" => %{"question" => raw}}, socket) do
    mark = Pages.get_mark!(socket.assigns.current_scope, id)
    question = String.trim(raw)

    cond do
      socket.assigns.busy or mark.text_id != socket.assigns.text.id or mark.kind not in ["answer", "definition"] ->
        {:noreply, socket}

      question == "" or String.length(question) > 500 or length(mark.replies) >= 20 ->
        {:noreply, assign(socket, error: "Ask up to 500 characters. Each annotation can keep 20 follow-ups.")}

      true ->
        history =
          [%{question: mark.question || "Define", answer: mark.body}] ++
            Enum.map(mark.replies, &%{question: &1.question, answer: &1.body})

        blocks = socket.assigns.document.blocks

        {:noreply,
         socket
         |> assign(
           busy: true,
           active_mark_id: id,
           pending: %{
             mark_id: id,
             mark: mark,
             action: "follow",
             question: question,
             quote: mark.quote,
             block_index: mark.block_index
           },
           error: nil
         )
         |> refresh_marks()
         |> start_page_help("ask", mark.quote, blocks, question, history)}
    end
  end

  def handle_event("retry-mark", %{"id" => id}, socket) do
    mark = Pages.get_mark!(socket.assigns.current_scope, id)

    if !socket.assigns.busy and mark.text_id == socket.assigns.text.id and mark.kind in ["answer", "definition"] do
      action =
        cond do
          mark.question == "Dictionary" -> "dictionary"
          mark.kind == "definition" -> "define"
          true -> "ask"
        end

      blocks = socket.assigns.document.blocks

      {:noreply,
       socket
       |> assign(
         busy: true,
         active_mark_id: id,
         pending: %{
           mark_id: id,
           mark: mark,
           action: "retry",
           question: mark.question || "Explain",
           quote: mark.quote,
           block_index: mark.block_index
         },
         error: nil
       )
       |> refresh_marks()
       |> start_help(action, mark.quote, blocks, mark.question || "Explain", mark.block_index)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("selection-mode", %{"mode" => mode}, socket) when mode in ~w(actions note ask pot),
    do: {:noreply, assign(socket, selection_mode: mode)}

  def handle_event("selection-mode", _, socket), do: {:noreply, socket}

  def handle_event("highlight", %{"color" => color}, socket) when color in ~w(yellow green blue rose) do
    socket = socket |> assign(marker_color: color) |> push_event("reading-preference", %{key: "marker", value: color})
    keep_mark(socket, %{kind: "highlight", color: color})
  end

  def handle_event("note", %{"note" => attrs}, %{assigns: %{editing_mark_id: id}} = socket) when not is_nil(id) do
    case Pages.update_mark(socket.assigns.current_scope, id, %{body: attrs["body"]}) do
      {:ok, _} -> {:noreply, socket |> assign(selection: nil, editing_mark_id: nil, error: nil) |> refresh_marks()}
      {:error, _} -> {:noreply, assign(socket, error: "Write a note between 1 and 4,000 characters.")}
    end
  end

  def handle_event("note", %{"note" => attrs}, socket),
    do: keep_mark(assign(socket, note_form: to_form(attrs, as: "note")), %{kind: "note", body: attrs["body"]})

  def handle_event("edit-note", %{"id" => id}, socket) do
    mark = Pages.get_mark!(socket.assigns.current_scope, id)

    if mark.text_id == socket.assigns.text.id and mark.kind == "note" do
      {:noreply,
       assign(socket,
         editing_mark_id: mark.id,
         selection: %{quote: mark.quote},
         selection_anchor: nil,
         selection_mode: "note",
         note_form: to_form(%{"body" => mark.body}, as: "note")
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("export-notebook", %{"mode" => mode}, socket) when mode in ["copy", "download"] do
    entries = Pages.list_marks(socket.assigns.current_scope, socket.assigns.text.id)

    markdown = notebook_markdown(socket.assigns.page_title, entries)

    {:noreply, push_event(socket, "page-export", %{mode: mode, markdown: markdown})}
  end

  def handle_event("notebook", _, socket),
    do: {:noreply, socket |> assign(notebook_open: !socket.assigns.notebook_open) |> refresh_marks()}

  def handle_event("filter-notebook", %{"kind" => kind}, socket) when kind in ~w(all highlight note definition answer),
    do: {:noreply, socket |> assign(notebook_filter: kind) |> refresh_marks()}

  def handle_event("remove-mark", %{"id" => id}, socket) do
    mark = Pages.get_mark!(socket.assigns.current_scope, id)

    if mark.text_id == socket.assigns.text.id do
      socket =
        if socket.assigns.pending && socket.assigns.pending.mark_id == id,
          do: stop_page_help(socket),
          else: socket

      {:ok, _} = Pages.delete_mark(socket.assigns.current_scope, id)
      socket = if socket.assigns.active_mark_id == id, do: assign(socket, active_mark_id: nil), else: socket
      {:noreply, refresh_marks(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("jump-mark", %{"id" => id}, socket) do
    mark = Pages.get_mark!(socket.assigns.current_scope, id)

    if mark.text_id == socket.assigns.text.id do
      {:noreply, socket |> assign(notebook_open: false) |> push_event("page-jump", %{id: id})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark-to-pot", %{"id" => id}, socket) do
    mark = Pages.get_mark!(socket.assigns.current_scope, id)

    if mark.text_id == socket.assigns.text.id do
      {:noreply,
       assign(socket,
         selection: %{quote: mark.quote, block_index: mark.block_index, context: mark.quote},
         selection_anchor: nil,
         selection_mode: "pot",
         pot_form: to_form(%{"meaning" => mark.meaning, "category" => jar_category(mark.category)}, as: "pot")
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-pot", %{"pot" => attrs}, socket) do
    if socket.assigns.selection do
      result =
        Learning.save_word(socket.assigns.current_scope, %{
          term: socket.assigns.selection.quote,
          meaning: attrs["meaning"],
          category: attrs["category"],
          context: Map.get(socket.assigns.selection, :context, socket.assigns.selection.quote),
          status: "learning"
        })

      case result do
        {:ok, _} ->
          {:noreply, socket |> assign(selection: nil) |> put_flash(:info, "Saved to your word jars.")}

        {:error, _} ->
          {:noreply,
           assign(socket,
             pot_form: to_form(attrs, as: "pot"),
             error: "Add a meaning and select a word or expression up to 200 characters."
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("help", %{"action" => action} = params, socket)
      when action in ~w(define explain simplify ask dictionary) do
    question = String.trim(get_in(params, ["question", "question"]) || "")

    cond do
      socket.assigns.busy or is_nil(socket.assigns.selection_anchor) or is_nil(socket.assigns.selection) ->
        {:noreply, socket}

      action == "ask" and (question == "" or String.length(question) > 500) ->
        {:noreply, assign(socket, error: "Ask a question up to 500 characters.")}

      true ->
        selection = socket.assigns.selection
        document = socket.assigns.document

        {:noreply,
         socket
         |> assign(
           busy: true,
           selection: nil,
           active_mark_id: nil,
           pending: %{
             anchor: socket.assigns.selection_anchor,
             action: action,
             question: question,
             quote: selection.quote,
             block_index: selection.block_index,
             mark_id: nil
           },
           error: nil
         )
         |> refresh_marks()
         |> push_event("page-pending", %{
           from: selection.from_offset,
           to: selection.to_offset,
           block: selection.block_index
         })
         |> start_help(action, selection.quote, document.blocks, question, selection.block_index)}
    end
  end

  @impl true
  def handle_info({:help_fragment, id, fragment}, %{assigns: %{help_stream: %{id: id} = preview, busy: true}} = socket)
      when is_binary(fragment) and fragment != "" do
    raw = String.slice(preview.raw <> fragment, 0, 32_000)
    timer = preview.timer || Process.send_after(self(), {:flush_help, id}, 60)
    {:noreply, assign(socket, help_stream: %{preview | raw: raw, timer: timer})}
  end

  def handle_info({:help_fragment, _, _}, socket), do: {:noreply, socket}

  def handle_info({:flush_help, id}, %{assigns: %{help_stream: %{id: id} = preview, busy: true}} = socket) do
    answer = preview.raw |> AnswerStream.preview() |> String.slice(0, 4000)
    socket = assign(socket, help_stream: %{preview | answer: answer, timer: nil})

    socket =
      if socket.assigns.pending.mark_id,
        do: stream_insert(socket, :margin_marks, socket.assigns.pending.mark),
        else: socket

    {:noreply, socket}
  end

  def handle_info({:flush_help, _}, socket), do: {:noreply, socket}

  def handle_info({:page_generation_delta, id, delta}, %{assigns: %{generation_id: id, editing: true}} = socket)
      when is_binary(delta) and delta != "" do
    preview = socket.assigns.generation_preview
    text = String.slice(preview.text <> delta, 0, 12_000)
    timer = preview.timer || Process.send_after(self(), {:flush_page_generation, id}, 60)
    {:noreply, assign(socket, generation_preview: %{text: text, timer: timer})}
  end

  def handle_info({:page_generation_delta, _, _}, socket), do: {:noreply, socket}

  def handle_info({:flush_page_generation, id}, %{assigns: %{generation_id: id, editing: true}} = socket) do
    preview = socket.assigns.generation_preview

    {:noreply,
     socket
     |> assign(generation_preview: %{preview | timer: nil})
     |> push_event("page-ai-chunk", %{request_id: id, html: WritingDocument.render(preview.text)})}
  end

  def handle_info({:flush_page_generation, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_async({:generate_page, id}, result, %{assigns: %{generation_id: id, editing: true}} = socket) do
    payload =
      case result do
        {:ok, {:ok, %{"markdown" => markdown}}} ->
          %{request_id: id, markdown: markdown}

        {:ok, {:error, :unavailable}} ->
          %{request_id: id, error: "AI is unavailable. Configure the Claude API key to generate text."}

        {:ok, {:error, :invalid_input}} ->
          %{request_id: id, error: "Describe what to write using 1–2,000 characters."}

        _ ->
          %{request_id: id, error: "Couldn’t generate the text. Your draft is safe. Try again."}
      end

    {:noreply, socket |> reset_page_generation() |> push_event("page-ai-result", payload)}
  end

  def handle_async({:generate_page, _}, _, socket), do: {:noreply, socket}

  def handle_async(:help, _, %{assigns: %{pending: nil}} = socket), do: {:noreply, socket}

  def handle_async(:help, {:ok, {:ok, data}}, socket) do
    pending = socket.assigns.pending

    attrs = %{
      kind: if(pending.action in ["define", "dictionary"], do: "definition", else: "answer"),
      body: data["answer"],
      meaning: data["meaning"],
      category: data["category"],
      question: if(pending.question == "", do: String.capitalize(pending.action), else: pending.question)
    }

    result =
      case pending.action do
        "follow" ->
          Pages.append_reply(socket.assigns.current_scope, pending.mark_id, %{
            question: pending.question,
            body: data["answer"]
          })

        "retry" ->
          Pages.update_mark(socket.assigns.current_scope, pending.mark_id, %{
            body: data["answer"],
            meaning: data["meaning"],
            category: data["category"]
          })

        _ ->
          Pages.create_mark(socket.assigns.current_scope, socket.assigns.text.id, pending.anchor, attrs)
      end

    socket = socket |> reset_help_stream() |> assign(busy: false, pending: nil)

    case result do
      {:ok, mark} -> {:noreply, socket |> assign(active_mark_id: mark.id) |> refresh_marks()}
      {:error, _} -> {:noreply, socket |> assign(error: "Couldn’t keep the answer. The page is safe.") |> refresh_marks()}
    end
  end

  def handle_async(:help, {:ok, {:error, reason}}, %{assigns: %{pending: pending}} = socket)
      when pending.action == "dictionary" or
             (pending.action == "retry" and pending.mark.kind == "definition" and pending.mark.question == "Dictionary") do
    error =
      if reason == :not_found,
        do: "No dictionary entry for this selection. Try a single word.",
        else: "The dictionary is unavailable right now. Try again in a moment."

    {:noreply, socket |> reset_help_stream() |> assign(busy: false, pending: nil, error: error) |> refresh_marks()}
  end

  def handle_async(:help, _, socket),
    do:
      {:noreply,
       socket
       |> reset_help_stream()
       |> assign(
         busy: false,
         pending: nil,
         error: "The tutor couldn’t respond. Your page and annotations are safe. Select the passage to try again."
       )
       |> refresh_marks()}

  defp start_help(socket, "dictionary", quote, blocks, _question, block_index) do
    context = Enum.at(blocks, block_index, %{text: quote}).text

    socket
    |> assign(help_stream: nil)
    |> start_async(:help, fn ->
      with {:ok, entry} <- Dictionary.lookup(quote, context) do
        category = entry.meanings |> List.first(%{}) |> Map.get(:part_of_speech) |> Dictionary.jar_category()
        {:ok, %{"answer" => Dictionary.markdown(entry), "meaning" => entry.translation || "", "category" => category}}
      end
    end)
  end

  defp start_help(socket, action, quote, blocks, question, _block_index),
    do: start_page_help(socket, action, quote, blocks, question)

  defp start_page_help(socket, action, quote, blocks, question, history \\ []) do
    owner = self()
    id = make_ref()
    preferences = Accounts.get_preferences(socket.assigns.current_scope)

    socket
    |> assign(help_stream: %{id: id, raw: "", answer: "", timer: nil})
    |> start_async(:help, fn ->
      Language.page_help(
        action,
        quote,
        blocks,
        question,
        history,
        fn fragment -> send(owner, {:help_fragment, id, fragment}) end,
        preferences
      )
    end)
  end

  defp reset_help_stream(socket) do
    if socket.assigns.help_stream && socket.assigns.help_stream.timer,
      do: Process.cancel_timer(socket.assigns.help_stream.timer)

    assign(socket, help_stream: nil)
  end

  defp stop_page_help(socket) do
    socket |> cancel_async(:help) |> reset_help_stream() |> assign(busy: false, pending: nil)
  end

  defp cancel_page_generation(%{assigns: %{generation_id: nil}} = socket), do: socket

  defp cancel_page_generation(socket) do
    socket |> cancel_async({:generate_page, socket.assigns.generation_id}) |> reset_page_generation()
  end

  defp reset_page_generation(socket) do
    if socket.assigns.generation_preview.timer, do: Process.cancel_timer(socket.assigns.generation_preview.timer)
    assign(socket, generation_id: nil, generation_preview: %{text: "", timer: nil})
  end

  defp jar_category("aux"), do: "verb"
  defp jar_category("proper"), do: "noun"
  defp jar_category(category) when category in ~w(noun verb adj adv pron prep expression), do: category
  defp jar_category(_), do: "word"

  defp keep_mark(%{assigns: %{selection_anchor: nil}} = socket, _attrs), do: {:noreply, socket}

  defp keep_mark(socket, attrs) do
    case Pages.create_mark(socket.assigns.current_scope, socket.assigns.text.id, socket.assigns.selection_anchor, attrs) do
      {:ok, mark} -> {:noreply, socket |> assign(selection: nil, error: nil, active_mark_id: mark.id) |> refresh_marks()}
      {:error, _} -> {:noreply, assign(socket, error: "Write a note between 1 and 4,000 characters.")}
    end
  end

  defp refresh_marks(socket, jump_id \\ nil)
  defp refresh_marks(%{assigns: %{text: nil}} = socket, _jump_id), do: socket

  defp refresh_marks(socket, jump_id) do
    marks = Pages.list_marks(socket.assigns.current_scope, socket.assigns.text.id)
    jump = Enum.find(marks, &(&1.id == jump_id))
    socket = if jump, do: assign(socket, active_mark_id: jump.id), else: socket

    mapped =
      Enum.map(marks, fn mark ->
        location = PageDocument.locate(socket.assigns.document, mark)

        %{
          id: mark.id,
          kind: mark.kind,
          color: mark.color,
          quote: mark.quote,
          active: mark.id == socket.assigns.active_mark_id,
          from: location && location.from_offset,
          to: location && location.to_offset,
          block: location && location.block_index
        }
      end)

    filtered = Enum.filter(marks, &(socket.assigns.notebook_filter == "all" or &1.kind == socket.assigns.notebook_filter))

    socket =
      socket
      |> assign(
        mark_count: length(marks),
        marks_json: Jason.encode!(mapped),
        notebook_markdown: notebook_markdown(socket.assigns.page_title, marks)
      )
      |> stream(:margin_marks, Enum.reject(marks, &(&1.kind == "highlight")), reset: true)
      |> stream(:notebook_marks, filtered, reset: true)
      |> push_event("page-marks", %{marks: mapped})

    if Enum.any?(mapped, &(&1.id == jump_id && &1.block != nil)),
      do: push_event(socket, "page-jump", %{id: jump_id}),
      else: socket
  end

  defp mark_title(%{kind: "note"}), do: "Note"
  defp mark_title(%{kind: "definition", question: "Dictionary"}), do: "Dictionary"
  defp mark_title(%{kind: "definition"}), do: "Define"
  defp mark_title(%{question: question}) when question in ["Explain", "Simplify"], do: question
  defp mark_title(_), do: "Ask"

  defp answer_html(markdown, document),
    do: Phoenix.HTML.raw(PageDocument.render_answer(markdown, length(document.blocks)))

  defp answer_summary(markdown), do: PageDocument.prepare(markdown).text

  defp mark_markdown(mark),
    do:
      "> #{String.replace(mark.quote, "\n", "\n> ")}\n\n#{mark.body}" <>
        Enum.map_join(mark.replies, "", &"\n\n### #{&1.question}\n\n#{&1.body}")

  defp notebook_markdown(title, marks),
    do:
      "# #{title}\n\n" <>
        Enum.map_join(marks, "\n\n", &"## #{String.capitalize(&1.kind)} · ¶#{&1.block_index + 1}\n\n#{mark_markdown(&1)}")
end
