defmodule LeitorWeb.WritingLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Language
  alias Leitor.Learning
  alias Leitor.WritingDocument

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Writing",
       writing_title: nil,
       generating_title: false,
       form: to_form(%{"text" => ""}, as: :writing),
       document_format: "plain",
       feedback_format: "plain",
       preview: false,
       feedback: nil,
       feedback_text: nil,
       feedback_index: 0,
       active_paragraph: 0,
       paragraph_count: 1,
       word_count: 0,
       save_status: "Not saved yet",
       answer: nil,
       asking: false,
       question_form: to_form(%{"question" => ""}, as: :tutor),
       busy: false,
       started_at: System.monotonic_time(:second)
     )
     |> stream(
       :drafts,
       socket.assigns.current_scope |> Learning.recent_attempts() |> Enum.filter(&(&1.kind in ["writing", "draft"]))
     )}
  end

  @impl true
  def handle_event("suggest-title", _, %{assigns: %{generating_title: true}} = socket), do: {:noreply, socket}

  def handle_event("suggest-title", _, socket) do
    title = socket.assigns.writing_title

    {:noreply,
     socket |> assign(generating_title: true) |> start_async(:writing_title, fn -> Language.writing_title(title) end)}
  end

  def handle_event("edit", %{"writing" => %{"text" => text} = attrs}, socket) do
    {:noreply, socket |> editor(text, WritingDocument.format(attrs)) |> assign(save_status: "Unsaved changes")}
  end

  def handle_event("paragraph", %{"index" => index}, socket) when is_integer(index) and index >= -1,
    do: {:noreply, assign(socket, active_paragraph: index)}

  def handle_event("feedback", %{"intent" => "save"} = params, socket), do: handle_event("save", params, socket)

  def handle_event("feedback", %{"writing" => %{"text" => text} = attrs}, socket) do
    index = paragraph_index(attrs, socket)
    format = WritingDocument.format(attrs)
    paragraph = WritingDocument.paragraph(text, format, index)

    cond do
      socket.assigns.busy ->
        {:noreply, socket}

      is_nil(paragraph) or String.length(text) > 10_000 ->
        {:noreply, put_flash(socket, :error, "Write between 1 and 10,000 characters.")}

      true ->
        {:noreply,
         socket
         |> editor(text, format)
         |> assign(busy: true, feedback: nil, feedback_text: text, feedback_index: index, feedback_format: format)
         |> start_async(:feedback, fn -> Language.feedback(paragraph.text) end)}
    end
  end

  def handle_event("save", %{"writing" => %{"text" => text} = attrs}, socket) do
    case Learning.create_attempt(socket.assigns.current_scope, %{
           kind: "draft",
           content: text,
           result: %{"format" => WritingDocument.format(attrs)},
           duration: elapsed(socket)
         }) do
      {:ok, attempt} ->
        {:noreply,
         socket
         |> editor(text, WritingDocument.format(attrs))
         |> assign(save_status: "Draft saved")
         |> stream_insert(:drafts, attempt, at: 0, limit: 50)
         |> put_flash(:info, "Draft saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Write something first, up to 10,000 characters.")}
    end
  end

  def handle_event("load", %{"id" => id}, socket) do
    attempt = Learning.get_attempt!(socket.assigns.current_scope, id)

    format = WritingDocument.format(attempt.result)

    feedback =
      if attempt.kind == "writing" &&
           (Map.has_key?(attempt.result, "paragraph_index") ||
              length(WritingDocument.paragraphs(attempt.content, format)) == 1),
         do: attempt.result

    {:noreply,
     socket
     |> cancel_async(:feedback)
     |> cancel_async(:question)
     |> editor(attempt.content, format)
     |> assign(
       answer: nil,
       asking: false,
       feedback: feedback,
       feedback_text: attempt.content,
       feedback_format: format,
       feedback_index: Map.get(attempt.result, "paragraph_index", 0),
       active_paragraph: 0,
       save_status: "Draft loaded",
       busy: false
     )
     |> push_event("writing-loaded", %{text: attempt.content, format: format})}
  end

  def handle_event("apply", params, %{assigns: %{feedback: %{"corrected" => corrected}}} = socket) do
    text = Map.get(params, "text", socket.assigns.form[:text].value)
    index = socket.assigns.feedback_index
    format = socket.assigns.feedback_format
    current = WritingDocument.paragraph(text, format, index)
    original = WritingDocument.paragraph(socket.assigns.feedback_text, format, index)

    if Map.get(params, "format", socket.assigns.document_format) == format &&
         current && original && current.text == original.text &&
         length(WritingDocument.paragraphs(text, format)) ==
           length(WritingDocument.paragraphs(socket.assigns.feedback_text, format)) do
      updated =
        binary_part(text, 0, current.start) <>
          corrected <>
          binary_part(text, current.start + current.length, byte_size(text) - current.start - current.length)

      if String.length(updated) <= 10_000 do
        {:noreply,
         socket
         |> editor(updated)
         |> assign(feedback: nil, save_status: "Unsaved changes")
         |> push_event("writing-applied", %{text: updated, index: index})}
      else
        {:noreply, put_flash(socket, :error, "This version exceeds the 10,000 character limit.")}
      end
    else
      {:noreply,
       socket
       |> editor(text)
       |> assign(feedback: nil)
       |> put_flash(:info, "This paragraph has changed. Review it again before applying a suggestion.")}
    end
  end

  def handle_event("apply", _params, socket), do: {:noreply, socket}

  def handle_event("review", %{"index" => index}, %{assigns: %{feedback: %{"issues" => issues}}} = socket) do
    with {i, ""} when i >= 0 <- Integer.parse(index),
         %{"to" => term, "explanation" => meaning} <- Enum.at(issues, i),
         {:ok, _entry} <-
           Learning.save_word(socket.assigns.current_scope, %{
             term: term,
             meaning: meaning,
             category: "error",
             context: socket.assigns.feedback["corrected"]
           }) do
      {:noreply, put_flash(socket, :info, "Correction added to your review queue.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "This correction could not be saved. Try a shorter phrase.")}
    end
  end

  def handle_event("review", _params, socket), do: {:noreply, socket}

  def handle_event("ask", %{"tutor" => %{"question" => question, "text" => text} = attrs}, socket) do
    question = String.trim(question)
    format = WritingDocument.format(attrs)
    paragraph = WritingDocument.paragraph(text, format, paragraph_index(attrs, socket))

    if not is_nil(paragraph) and question != "" and String.length(question) <= 500 and text != "" and
         String.length(text) <= 10_000 and
         !socket.assigns.asking do
      {:noreply,
       socket
       |> editor(text, format)
       |> assign(asking: true, answer: nil)
       |> start_async(:question, fn -> Language.explain(paragraph.text, question) end)}
    else
      {:noreply, put_flash(socket, :error, "Write some text and a question of up to 500 characters first.")}
    end
  end

  def handle_event("close-answer", _params, socket),
    do: {:noreply, socket |> cancel_async(:question) |> assign(answer: nil, asking: false)}

  def handle_event("toggle-preview", _, socket), do: {:noreply, assign(socket, preview: !socket.assigns.preview)}

  @impl true
  def handle_async(:writing_title, {:ok, {:ok, %{"title" => title}}}, socket) when is_binary(title) do
    if String.trim(title) != "" and String.length(title) <= 100 do
      {:noreply, assign(socket, writing_title: String.trim(title), generating_title: false)}
    else
      handle_async(:writing_title, {:error, :invalid_response}, socket)
    end
  end

  def handle_async(:writing_title, _failure, socket) do
    {:noreply,
     socket
     |> assign(generating_title: false)
     |> put_flash(:error, "Could not suggest a title. Please try again.")}
  end

  def handle_async(:feedback, {:ok, {:ok, feedback}}, socket) do
    case Learning.create_attempt(socket.assigns.current_scope, %{
           kind: "writing",
           content: socket.assigns.feedback_text,
           result:
             feedback
             |> Map.put("paragraph_index", socket.assigns.feedback_index)
             |> Map.put("format", socket.assigns.feedback_format),
           duration: elapsed(socket)
         }) do
      {:ok, attempt} ->
        socket = socket |> assign(feedback: feedback, busy: false) |> stream_insert(:drafts, attempt, at: 0, limit: 50)
        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(feedback: feedback, busy: false)
         |> put_flash(:error, "Feedback is ready, but saving failed. Please save again.")}
    end
  end

  def handle_async(:feedback, _failure, socket),
    do:
      {:noreply,
       socket
       |> assign(busy: false)
       |> put_flash(:error, "The tutor is unavailable. Your text is preserved; try again shortly.")}

  def handle_async(:question, {:ok, {:ok, %{"answer" => answer}}}, socket),
    do: {:noreply, assign(socket, answer: answer, asking: false)}

  def handle_async(:question, _failure, socket),
    do: {:noreply, socket |> assign(asking: false) |> put_flash(:error, "The tutor is unavailable. Please try again.")}

  defp paragraph_index(attrs, socket) do
    case Integer.parse(to_string(Map.get(attrs, "paragraph", socket.assigns.active_paragraph))) do
      {index, ""} when index >= -1 -> index
      _ -> 0
    end
  end

  defp editor(socket, text, format \\ nil) do
    format = format || socket.assigns.document_format
    count = length(WritingDocument.paragraphs(text, format))

    assign(socket,
      document_format: format,
      form: to_form(%{"text" => text}, as: :writing),
      paragraph_count: max(count, 1),
      word_count: WritingDocument.word_count(text, format),
      active_paragraph: min(socket.assigns.active_paragraph, max(count - 1, 0))
    )
  end

  defp elapsed(socket), do: min(max(System.monotonic_time(:second) - socket.assigns.started_at, 0), 1800)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="write"
      class="page writing-page"
      context_title={@writing_title || "Writing"}
      context_detail={
        if @active_paragraph < 0,
          do: "Select a paragraph",
          else: "Paragraph #{@active_paragraph + 1} of #{@paragraph_count}"
      }
    >
      <:header_controls>
        <p id="writing-save-status" class="writing-header-status" role="status">
          <span>{@word_count} words</span><span aria-hidden="true">·</span><span>{@save_status}</span>
        </p>
        <button
          id="suggest-writing-title"
          type="button"
          class="icon-button"
          phx-click="suggest-title"
          disabled={@generating_title}
          aria-label={
            if @generating_title, do: "Suggesting a writing title", else: "Suggest a writing title"
          }
          aria-busy={to_string(@generating_title)}
          title="Suggest a writing title"
        >
          <.icon
            name={if @generating_title, do: "hero-arrow-path", else: "hero-light-bulb"}
            class={["size-[18px]", @generating_title && "animate-spin"]}
          />
        </button>
        <details
          id="writing-history"
          class="writing-history"
          phx-window-keydown={
            JS.focus(to: "#writing-history[open] > summary")
            |> JS.remove_attribute("open", to: "#writing-history")
          }
          phx-key="Escape"
        >
          <summary
            id="writing-history-toggle"
            class="icon-button"
            aria-label="Writing history"
            title="Writing history"
          >
            <.icon name="hero-clock" class="size-[18px]" />
          </summary>
          <span
            id="writing-history-positioner"
            phx-hook="Floating"
            phx-update="ignore"
            data-panel="writing-history-panel"
            data-placement="bottom-end"
            hidden
          ></span>
          <section
            id="writing-history-panel"
            class="writing-history-panel floating-panel"
            aria-labelledby="writing-history-title"
            phx-click-away={JS.remove_attribute("open", to: "#writing-history")}
          >
            <h2 id="writing-history-title">Writing history</h2>
            <div id="writing-drafts" phx-update="stream">
              <p id="no-drafts" class="hidden only:block muted">
                Saved drafts and feedback will appear here.
              </p>
              <article :for={{id, draft} <- @streams.drafts} id={id} class="writing-history-entry">
                <button
                  class="writing-history-open"
                  phx-click={
                    JS.remove_attribute("open", to: "#writing-history")
                    |> JS.push("load", value: %{id: draft.id})
                  }
                >
                  <span class="eyebrow">{Calendar.strftime(draft.inserted_at, "%b %d · %H:%M")} · {draft.kind}</span>
                  <span class="writing-history-preview">{String.slice(draft.content, 0, 180)}</span>
                  <span class="text-link text-sm">Open writing <span aria-hidden="true">↗</span></span>
                </button>
              </article>
            </div>
          </section>
        </details>
        <button
          type="submit"
          form="writing-form"
          class="icon-button"
          disabled={@busy}
          name="intent"
          value="save"
          id="save-draft"
          aria-label="Save draft"
          title="Save draft"
        >
          <.icon name="hero-bookmark" class="size-4" />
        </button>
      </:header_controls>
      <h1 class="sr-only">Writing</h1>
      <div id="writing-title-region" aria-live="polite">
        <h2 :if={@writing_title} id="writing-title" class="writing-title">{@writing_title}</h2>
      </div>
      <.form
        for={@form}
        id="writing-form"
        phx-submit="feedback"
        phx-change="edit"
        class="writing-document"
      >
        <input
          id="writing-paragraph"
          type="hidden"
          name="writing[paragraph]"
          value={@active_paragraph}
        />
        <div hidden={@preview}>
          <div
            id="writing-editor"
            phx-hook="WritingEditor"
            phx-update="ignore"
            data-format={@document_format}
          >
            <input id="writing-format" type="hidden" name="writing[format]" value={@document_format} />
            <div hidden>
              <.input
                field={@form[:text]}
                type="textarea"
                label="Markdown source"
                class="writing-source"
                phx-debounce="250"
                maxlength="10000"
                hidden
              />
            </div>
            <div id="writing-surface"></div>
            <LeitorWeb.WritingComponents.slash_menu />
            <p id="writing-editor-status" class="writing-limit-message" role="status"></p>
          </div>
        </div>
        <article
          :if={@preview}
          id="writing-preview"
          class="writing-prose"
          aria-label="Writing preview"
        >
          <%= if @document_format == "markdown" do %>
            {Phoenix.HTML.raw(WritingDocument.render(@form[:text].value))}
          <% else %>
            <p :for={paragraph <- WritingDocument.paragraphs(@form[:text].value, "plain")}>
              {paragraph.text}
            </p>
          <% end %>
        </article>
      </.form>
      <p id="writing-help" class="sr-only">
        Type / for blocks, or use Markdown shortcuts. Enter starts a paragraph. The tutor reviews the paragraph under your cursor, excluding code blocks.
      </p>
      <section :if={@feedback} id="writing-feedback" class="stack" aria-live="polite">
        <div class="row between wrap">
          <p class="eyebrow">Paragraph {@feedback_index + 1} · Feedback</p><p>
            {@feedback["summary"]}
          </p>
        </div>
        <div class="practice-results">
          <article :for={{issue, index} <- Enum.with_index(@feedback["issues"])} class="card stack">
            <p><del>{issue["from"]}</del> → <strong>{issue["to"]}</strong></p><p class="muted">
              {issue["explanation"]}
            </p>
            <button
              id={"review-correction-#{index}"}
              class="icon-button"
              aria-label="Turn correction into a review card"
              title="Turn correction into a review card"
              phx-click="review"
              phx-value-index={index}
            ><.icon name="hero-arrow-path" class="size-5" /></button>
          </article>
        </div>
        <div class="writing-suggestion stack">
          <span class="eyebrow">A little more natural</span><p class="text-xl">
            {@feedback["corrected"]}
          </p>
          <button
            id="apply-correction"
            class="icon-button"
            aria-label="Use this version"
            title="Use this version"
            phx-click={JS.dispatch("writing:apply", to: "#writing-editor")}
          ><.icon name="hero-check-circle" class="size-5" /></button>
          <p :for={alternative <- @feedback["alternatives"]}>{alternative}</p>
        </div>
      </section>

      <section :if={@answer || @asking} class="tutor-answer stack" aria-live="polite">
        <div class="row between">
          <span class="eyebrow">About your paragraph</span><button
            class="icon-button"
            phx-click="close-answer"
            aria-label="Close answer"
            title="Close answer"
          ><.icon name="hero-x-mark" class="size-4" /></button>
        </div>
        <p>{if @asking, do: "Thinking…", else: @answer}</p>
      </section>
      <StudyComponents.reading_toolbar id="writing-toolbar" label="Writing tools">
        <button
          id="writing-preview-toggle"
          type="button"
          class="icon-button"
          phx-click="toggle-preview"
          aria-label="Preview Markdown"
          aria-pressed={to_string(@preview)}
          title="Preview Markdown"
        >
          <.icon name="hero-eye" class="size-5" />
        </button>
        <.form
          for={@question_form}
          id="writing-question"
          phx-submit="ask"
          phx-hook="WritingQuestion"
          class="dock-question"
        >
          <input type="hidden" name="tutor[text]" value="" />
          <input type="hidden" name="tutor[format]" value={@document_format} />
          <input type="hidden" name="tutor[paragraph]" value={@active_paragraph} />
          <.icon name="hero-sparkles" class="size-4" />
          <.input
            field={@question_form[:question]}
            id="writing-ask-input"
            aria-label="Ask about this paragraph"
            class="dock-input"
            placeholder="Ask about this paragraph…"
            maxlength="500"
            required
          />
          <button
            class="icon-button"
            disabled={@asking}
            aria-label="Ask the tutor"
            title="Ask the tutor"
          ><.icon
            name="hero-arrow-up"
            class="size-4"
          /></button>
        </.form>
        <button
          id="review-paragraph"
          type="submit"
          form="writing-form"
          class="action action-primary"
          disabled={@busy}
          aria-label="Review current paragraph"
          title="Review current paragraph"
          aria-busy={to_string(@busy)}
        >
          <.icon
            name={if @busy, do: "hero-arrow-path", else: "hero-check"}
            class={["size-5", @busy && "animate-spin"]}
          />
        </button>
      </StudyComponents.reading_toolbar>
    </Layouts.app>
    """
  end
end
