defmodule LeitorWeb.PracticeLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Language
  alias Leitor.Learning
  alias Leitor.Learning.Practice
  alias Leitor.Library
  alias Leitor.Library.Reading

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Practice",
       result: nil,
       busy: false,
       started_at: System.monotonic_time(:second),
       form: to_form(%{"answer" => ""}, as: :practice)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mode = if params["mode"] in ["dictation", "shadowing", "rewrite"], do: params["mode"], else: "dictation"
    text = if params["text"] not in [nil, ""], do: Library.get_text!(socket.assigns.current_scope, params["text"])
    sentences = if text, do: Reading.prepare(text.body), else: Reading.sample()

    index =
      case Integer.parse(params["sentence"] || "0") do
        {n, ""} -> n |> max(0) |> min(length(sentences) - 1)
        _ -> 0
      end

    {:noreply,
     socket
     |> cancel_async(:feedback)
     |> assign(
       mode: mode,
       title: if(text, do: text.title, else: "A Scandal in Bohemia"),
       text_id: if(text, do: text.id, else: ""),
       sentences: sentences,
       index: index,
       sentence: Enum.at(sentences, index),
       result: nil,
       busy: false,
       form: to_form(%{"answer" => ""}, as: :practice),
       started_at: System.monotonic_time(:second)
     )}
  end

  @impl true
  def handle_event("check", %{"practice" => %{"answer" => answer}}, socket) do
    answer = String.trim(answer)

    cond do
      socket.assigns.busy ->
        {:noreply, socket}

      answer == "" or String.length(answer) > 10_000 ->
        {:noreply, put_flash(socket, :error, "Write an answer of up to 10,000 characters.")}

      socket.assigns.mode == "rewrite" ->
        original = socket.assigns.sentence.body

        {:noreply,
         socket
         |> assign(busy: true, form: to_form(%{"answer" => answer}, as: :practice))
         |> start_async(:feedback, fn -> Language.feedback(answer, original) end)}

      socket.assigns.mode == "dictation" ->
        comparison = Practice.compare(socket.assigns.sentence.body, answer)

        {:ok, _} =
          Learning.create_attempt(socket.assigns.current_scope, %{
            kind: "dictation",
            content: answer,
            result: %{score: comparison.score, original: socket.assigns.sentence.body},
            duration: elapsed(socket)
          })

        {:noreply, assign(socket, result: comparison, form: to_form(%{"answer" => answer}, as: :practice))}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("recorded", %{"duration" => duration}, socket) when is_integer(duration) and duration in 1..60 do
    if socket.assigns.mode == "shadowing" do
      {:ok, _} =
        Learning.create_attempt(socket.assigns.current_scope, %{
          kind: "shadowing",
          content: socket.assigns.sentence.body,
          result: %{method: "self_assessment"},
          duration: duration
        })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:feedback, {:ok, {:ok, feedback}}, socket) do
    {:ok, _} =
      Learning.create_attempt(socket.assigns.current_scope, %{
        kind: "rewrite",
        content: socket.assigns.form[:answer].value,
        result: feedback,
        duration: elapsed(socket)
      })

    {:noreply, assign(socket, result: feedback, busy: false)}
  end

  def handle_async(:feedback, _failure, socket),
    do:
      {:noreply,
       socket
       |> assign(busy: false)
       |> put_flash(:error, "The tutor is unavailable. Your answer is still here; please try again.")}

  defp elapsed(socket), do: min(max(System.monotonic_time(:second) - socket.assigns.started_at, 0), 1800)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="practice"
      class="page practice-page"
      context_title={String.capitalize(@mode)}
      context_detail={"#{@title} · Sentence #{@index + 1} of #{length(@sentences)}"}
    >
      <:header_controls>
        <nav class="reading-layers" aria-label="Practice activity">
          <.link
            :for={
              {mode, icon} <- [
                {"dictation", "hero-speaker-wave"},
                {"shadowing", "hero-microphone"},
                {"rewrite", "hero-pencil-square"}
              ]
            }
            patch={~p"/practice?#{%{mode: mode, text: @text_id, sentence: @index}}"}
            class={["layer-button", @mode == mode && "active"]}
            aria-label={String.capitalize(mode)}
            title={String.capitalize(mode)}
            aria-current={if @mode == mode, do: "page"}
          >
            <.icon name={icon} class="size-4" />
          </.link>
        </nav>
      </:header_controls>
      <h1 class="sr-only">{String.capitalize(@mode)} practice</h1>
      <div :if={@mode == "rewrite"} class="stack">
        <span class="eyebrow">Original</span>
        <p class="practice-original">{@sentence.body}</p>
      </div>
      <p :if={@mode == "shadowing"} class="shadow-sentence">{@sentence.body}</p>
      <section :if={@mode != "rewrite"} class="practice-audio" aria-label="Original sentence audio">
        <button
          id="practice-listen"
          class="audio-play"
          aria-label="Listen to the original"
          phx-click={JS.dispatch("leitor:speak", detail: %{text: @sentence.body, rate: 1})}
        >
          <.icon name="hero-play-solid" class="size-7" />
        </button>
        <div class="audio-illustration">
          <div class="audio-bars" aria-hidden="true">
            <span
              :for={
                height <- [
                  24,
                  45,
                  65,
                  34,
                  78,
                  95,
                  60,
                  36,
                  82,
                  56,
                  90,
                  42,
                  65,
                  30,
                  48,
                  85,
                  100,
                  74,
                  48,
                  64,
                  38,
                  60,
                  93,
                  40,
                  65,
                  34,
                  78,
                  95,
                  60,
                  36,
                  82,
                  56,
                  90,
                  42,
                  65,
                  30,
                  48,
                  85,
                  100,
                  74,
                  48,
                  64,
                  38,
                  60,
                  93,
                  40,
                  30,
                  16
                ]
              }
              style={"height: #{height}%"}
            ></span>
          </div>
          <span class="muted text-sm">Listen, then {if @mode == "dictation",
            do: "write what you hear",
            else: "match the rhythm"}.</span>
        </div>
        <button
          id="practice-listen-slow"
          class="action"
          phx-click={JS.dispatch("leitor:speak", detail: %{text: @sentence.body, rate: 0.75})}
        >0.75×</button>
      </section>
      <.form
        :if={@mode in ["dictation", "rewrite"]}
        for={@form}
        id="practice-form"
        phx-submit="check"
        class="practice-answer stack"
      >
        <.input
          field={@form[:answer]}
          type="textarea"
          rows="3"
          class="practice-text"
          label={if @mode == "rewrite", do: "In your own words", else: "What did you hear?"}
          placeholder={
            if @mode == "rewrite", do: "Find another way to say it…", else: "Write the sentence…"
          }
          maxlength="10000"
          required
          spellcheck={@mode != "dictation"}
        />
        <div class="row wrap">
          <.button disabled={@busy} phx-disable-with="Checking…">{if @busy,
            do: "Thinking…",
            else: "Check my answer"}</.button>
        </div>
      </.form>
      <section
        :if={@mode == "shadowing"}
        class="practice-audio shadow-recorder"
        aria-label="Your recording"
      >
        <div
          id={"recorder-#{@text_id}-#{@index}"}
          phx-hook="ShadowingRecorder"
          phx-update="ignore"
          class="stack items-center"
        >
          <button type="button" class="record-button"><span class="record-dot" aria-hidden="true"></span><span class="record-label sr-only">Start recording</span></button>
          <audio controls hidden aria-label="Your recording"></audio>
          <p role="status" class="muted text-sm">
            Recordings stay on your device. We save practice time, not your audio.
          </p>
        </div>
      </section>
      <section :if={@result && @mode == "dictation"} id="dictation-result" role="status" class="stack">
        <span class="eyebrow">What you wrote</span>
        <p class="dictation-comparison">
          <span
            :for={{kind, words} <- @result.parts}
            class={[
              kind == :del && "missing-word",
              kind == :ins && "added-word",
              kind == :eq && "matched-word"
            ]}
          >
            <span :if={kind == :del} class="comparison-label">Missing</span>
            <span :if={kind == :ins} class="sr-only">Added:</span>{Enum.join(words, " ")}
          </span>
        </p>
        <div class="practice-results">
          <article class="card stack">
            <span class="eyebrow">Result</span><h2 class="result-number">
              {@result.score}% word match
            </h2><p class="muted">{@result.correct} of {@result.total} original words recalled.</p>
          </article>
          <article class="focus-card stack">
            <span class="eyebrow">Listen again</span><p class="text-xl">{@sentence.body}</p><p>
              Missing and added words affect the score. Listen slowly and try the sentence again.
            </p>
          </article>
        </div>
      </section>
      <section :if={@result && @mode == "rewrite"} id="rewrite-result" role="status" class="stack">
        <p>{@result["summary"]}</p>
        <div class="practice-results">
          <article :for={issue <- @result["issues"]} class="card stack">
            <p><del>{issue["from"]}</del> → <strong>{issue["to"]}</strong></p><p class="muted">
              {issue["explanation"]}
            </p>
          </article>
        </div>
        <div class="focus-card stack">
          <span class="eyebrow">Other ways to say it</span><p class="text-xl">
            {@result["corrected"]}
          </p><p :for={alternative <- @result["alternatives"]}>{alternative}</p>
        </div>
      </section>
      <nav class="row justify-center wrap" aria-label="Sentence navigation">
        <.link
          :if={@index > 0}
          patch={~p"/practice?#{%{mode: @mode, text: @text_id, sentence: @index - 1}}"}
          class="action"
        >Previous</.link>
        <.link
          :if={@index < length(@sentences) - 1}
          patch={~p"/practice?#{%{mode: @mode, text: @text_id, sentence: @index + 1}}"}
          class="action action-primary"
        >Next sentence <.icon name="hero-arrow-right" class="size-4" /></.link>
      </nav>
    </Layouts.app>
    """
  end
end
