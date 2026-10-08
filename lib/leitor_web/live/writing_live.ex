defmodule LeitorWeb.WritingLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Language
  alias Leitor.Learning

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Writing",
       form: to_form(%{"text" => ""}, as: :writing),
       feedback: nil,
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
  def handle_event("feedback", %{"intent" => "save"} = params, socket), do: handle_event("save", params, socket)

  def handle_event("feedback", %{"writing" => %{"text" => text}}, socket) do
    text = String.trim(text)

    cond do
      socket.assigns.busy ->
        {:noreply, socket}

      text == "" or String.length(text) > 10_000 ->
        {:noreply, put_flash(socket, :error, "Write between 1 and 10,000 characters.")}

      true ->
        {:noreply,
         socket
         |> assign(busy: true, feedback: nil, form: to_form(%{"text" => text}, as: :writing))
         |> start_async(:feedback, fn -> Language.feedback(text) end)}
    end
  end

  def handle_event("save", %{"writing" => %{"text" => text}}, socket) do
    case Learning.create_attempt(socket.assigns.current_scope, %{
           kind: "draft",
           content: String.trim(text),
           result: %{},
           duration: elapsed(socket)
         }) do
      {:ok, attempt} ->
        {:noreply, socket |> stream_insert(:drafts, attempt, at: 0, limit: 50) |> put_flash(:info, "Draft saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Write something first, up to 10,000 characters.")}
    end
  end

  def handle_event("load", %{"id" => id}, socket) do
    attempt = Learning.get_attempt!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> cancel_async(:feedback)
     |> cancel_async(:question)
     |> assign(answer: nil, asking: false)
     |> assign(
       form: to_form(%{"text" => attempt.content}, as: :writing),
       feedback: if(attempt.kind == "writing", do: attempt.result),
       busy: false
     )}
  end

  def handle_event("apply", _params, %{assigns: %{feedback: %{"corrected" => corrected}}} = socket),
    do: {:noreply, assign(socket, form: to_form(%{"text" => corrected}, as: :writing), feedback: nil)}

  def handle_event("review", %{"index" => index}, socket) do
    with {i, ""} <- Integer.parse(index),
         %{"to" => term, "explanation" => meaning} <- Enum.at(socket.assigns.feedback["issues"], i),
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

  def handle_event("ask", %{"tutor" => %{"question" => question, "text" => text}}, socket) do
    question = String.trim(question)
    text = String.trim(text)

    if question != "" and String.length(question) <= 500 and text != "" and String.length(text) <= 10_000 and
         !socket.assigns.asking do
      {:noreply,
       socket
       |> assign(asking: true, answer: nil, form: to_form(%{"text" => text}, as: :writing))
       |> start_async(:question, fn -> Language.explain(text, question) end)}
    else
      {:noreply, put_flash(socket, :error, "Write some text and a question of up to 500 characters first.")}
    end
  end

  def handle_event("close-answer", _params, socket),
    do: {:noreply, socket |> cancel_async(:question) |> assign(answer: nil, asking: false)}

  @impl true
  def handle_async(:feedback, {:ok, {:ok, feedback}}, socket) do
    case Learning.create_attempt(socket.assigns.current_scope, %{
           kind: "writing",
           content: socket.assigns.form[:text].value,
           result: feedback,
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

  defp elapsed(socket), do: min(max(System.monotonic_time(:second) - socket.assigns.started_at, 0), 1800)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="write"
      class="page writing-page"
      context_title="Writing"
    >
      <:header_controls>
        <button
          type="submit"
          form="writing-form"
          class="layer-button"
          disabled={@busy}
          name="intent"
          value="save"
          id="save-draft"
        ><.icon name="hero-bookmark" class="size-4" /> Save draft</button>
      </:header_controls>
      <h1 class="sr-only">Writing</h1>
      <div class="row wrap">
        <span class="eyebrow">Today's prompt</span><p class="muted">
          Describe a small moment that stayed with you.
        </p>
      </div>
      <.form for={@form} id="writing-form" phx-submit="feedback" class="stack">
        <.input
          field={@form[:text]}
          type="textarea"
          label="Your English text"
          class="essay-input"
          rows="10"
          maxlength="10000"
          required
          placeholder="Write in English…"
          spellcheck="false"
        />
      </.form>
      <p class="muted text-sm">
        Your text is sent to Anthropic when you ask the tutor or request feedback.
      </p>
      <section :if={@feedback} id="writing-feedback" class="stack" aria-live="polite">
        <p>{@feedback["summary"]}</p>
        <div class="practice-results">
          <article :for={{issue, index} <- Enum.with_index(@feedback["issues"])} class="card stack">
            <p><del>{issue["from"]}</del> → <strong>{issue["to"]}</strong></p><p class="muted">
              {issue["explanation"]}
            </p>
            <button
              id={"review-correction-#{index}"}
              class="text-link"
              phx-click="review"
              phx-value-index={index}
            >Turn into a review card</button>
          </article>
        </div>
        <div class="focus-card stack">
          <span class="eyebrow">A little more natural</span><p class="text-xl">
            {@feedback["corrected"]}
          </p>
          <button id="apply-correction" class="action" phx-click="apply">Use this version</button>
          <p :for={alternative <- @feedback["alternatives"]}>{alternative}</p>
        </div>
      </section>
      <details class="writing-history">
        <summary>Your writing history</summary>
        <div id="writing-drafts" phx-update="stream" class="practice-results">
          <p id="no-drafts" class="hidden only:block muted">
            Saved drafts and feedback will appear here.
          </p>
          <article :for={{id, draft} <- @streams.drafts} id={id} class="card stack">
            <span class="eyebrow">{Calendar.strftime(draft.inserted_at, "%b %d · %H:%M")} · {draft.kind}</span>
            <p>{String.slice(draft.content, 0, 180)}</p><button
              class="text-link"
              phx-click="load"
              phx-value-id={draft.id}
            >Open writing</button>
          </article>
        </div>
      </details>
      <section :if={@answer || @asking} class="tutor-answer stack" aria-live="polite">
        <div class="row between">
          <span class="eyebrow">About your text</span><button
            class="icon-button"
            phx-click="close-answer"
            aria-label="Close answer"
          ><.icon name="hero-x-mark" class="size-4" /></button>
        </div>
        <p>{if @asking, do: "Thinking…", else: @answer}</p>
      </section>
      <.form
        for={@question_form}
        id="writing-question"
        phx-submit="ask"
        phx-hook="WritingQuestion"
        class="reader-dock writing-dock"
      >
        <input type="hidden" name="tutor[text]" value="" />
        <.input
          field={@question_form[:question]}
          label="Ask about your text"
          class="dock-input"
          placeholder="How do I say… / make it more formal…"
          maxlength="500"
          required
        />
        <button class="dock-next" disabled={@asking} aria-label="Ask the tutor"><.icon
          name="hero-arrow-up"
          class="size-5"
        /></button>
        <.button
          type="submit"
          form="writing-form"
          class="action action-primary"
          disabled={@busy}
          phx-disable-with="Thinking…"
        >{if @busy,
          do: "Thinking…",
          else: "Review my text"} <.icon name="hero-check" class="size-4" /></.button>
      </.form>
    </Layouts.app>
    """
  end
end
