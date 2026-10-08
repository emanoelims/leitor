defmodule LeitorWeb.LessonsLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Language
  alias Leitor.Learning
  alias Leitor.Library
  alias Leitor.Library.Import
  alias Leitor.Library.Reading

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Library.subscribe_texts(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(
       page_title: "Lesson materials",
       lesson: nil,
       import?: false,
       busy: false,
       count: 0,
       search: "",
       form: to_form(%{"title" => "", "body" => ""}, as: :material)
     )
     |> stream(:units, [])
     |> stream_configure(:vocabulary, dom_id: fn word -> "lesson-word-#{word["id"]}" end)
     |> stream(:vocabulary, [])
     |> allow_upload(:material,
       accept: ~w(.txt .pdf .epub .docx .jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    {:noreply, socket |> cancel_async(:guide) |> assign(busy: false) |> refresh(params["id"])}
  end

  @impl true
  def handle_event("new", _, socket), do: {:noreply, assign(socket, import?: !socket.assigns.import?)}

  def handle_event("validate", %{"material" => attrs}, socket),
    do: {:noreply, assign(socket, form: to_form(attrs, as: :material))}

  def handle_event("filter", %{"search" => search}, socket), do: {:noreply, socket |> assign(search: search) |> refresh()}
  def handle_event("cancel-upload", %{"ref" => ref}, socket), do: {:noreply, cancel_upload(socket, :material, ref)}

  def handle_event("import", %{"material" => attrs}, socket) do
    results =
      consume_uploaded_entries(socket, :material, fn %{path: path}, entry ->
        {:ok, Import.extract(path, entry.client_name)}
      end)

    result =
      case results do
        [result] -> result
        [] -> {:ok, attrs["body"] || ""}
      end

    save_material(socket, result, attrs)
  end

  def handle_event("analyze", _, %{assigns: %{busy: true}} = socket), do: {:noreply, socket}

  def handle_event("analyze", _, socket) do
    body = socket.assigns.lesson.body
    {:noreply, socket |> assign(busy: true) |> start_async(:guide, fn -> Language.lesson(body) end)}
  end

  def handle_event("save-word", %{"index" => raw}, socket) do
    with {index, ""} when index >= 0 <- Integer.parse(raw),
         %{"term" => term, "meaning" => meaning, "category" => category} <-
           Enum.at(socket.assigns.lesson.analysis["vocabulary"] || [], index),
         {:ok, _} <-
           Learning.save_word(socket.assigns.current_scope, %{
             term: term,
             meaning: meaning,
             category: category,
             context: String.slice(socket.assigns.lesson.body, 0, 3000)
           }) do
      {:noreply, put_flash(socket, :info, "Added to your word jar.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "This word couldn't be saved.")}
    end
  end

  @impl true
  def handle_async(:guide, {:ok, {:ok, analysis}}, socket) do
    case Library.update_text(socket.assigns.current_scope, socket.assigns.lesson, %{analysis: analysis}) do
      {:ok, lesson} ->
        {:noreply, socket |> assign(lesson: lesson, busy: false) |> stream_vocabulary()}

      {:error, _} ->
        {:noreply, socket |> assign(busy: false) |> put_flash(:error, "The guide couldn't be saved. Please try again.")}
    end
  end

  def handle_async(:guide, _failure, socket),
    do:
      {:noreply,
       socket
       |> assign(busy: false)
       |> put_flash(:error, "The tutor is unavailable. Your material is saved; try again shortly.")}

  @impl true
  def handle_info({:deleted, %Library.Text{id: id}}, %{assigns: %{lesson: %Library.Text{id: id}}} = socket),
    do: {:noreply, socket |> cancel_async(:guide) |> assign(busy: false) |> push_patch(to: ~p"/lessons")}

  def handle_info({event, %Library.Text{}}, socket) when event in [:created, :updated, :deleted],
    do: {:noreply, refresh(socket, socket.assigns.lesson && socket.assigns.lesson.id)}

  defp save_material(socket, {:error, reason}, _attrs), do: {:noreply, put_flash(socket, :error, reason)}

  defp save_material(socket, {:ok, body}, attrs) do
    case Library.create_text(socket.assigns.current_scope, %{
           title: attrs["title"],
           body: body,
           source: "lesson",
           position: 0
         }) do
      {:ok, lesson} ->
        {:noreply,
         socket
         |> assign(import?: false)
         |> put_flash(:info, "Material saved. Ready to read and practice.")
         |> push_patch(to: ~p"/lessons/#{lesson.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :material, action: :insert))}
    end
  end

  defp refresh(socket, id \\ nil) do
    units =
      socket.assigns.current_scope
      |> Library.list_texts()
      |> Enum.filter(
        &(&1.source == "lesson" && String.contains?(String.downcase(&1.title), String.downcase(socket.assigns.search)))
      )
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    lesson = if id, do: Library.get_text!(socket.assigns.current_scope, id), else: List.first(units)
    socket |> assign(lesson: lesson, count: length(units)) |> stream(:units, units, reset: true) |> stream_vocabulary()
  end

  defp stream_vocabulary(socket) do
    words = if socket.assigns.lesson, do: socket.assigns.lesson.analysis["vocabulary"] || [], else: []

    words =
      words |> Enum.with_index() |> Enum.map(fn {word, index} -> Map.merge(word, %{"id" => index, "index" => index}) end)

    stream(socket, :vocabulary, words, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="lessons"
      context_detail={"#{@count} imported units"}
      class="page lessons-page"
    >
      <:header_controls>
        <button id="import-unit" class="icon-button" phx-click="new" aria-label="Import a unit"><.icon
          name="hero-arrow-up-tray"
          class="size-[18px]"
        /></button><button
          id="import-photo"
          phx-click="new"
          class="icon-button"
          aria-label="Import a page photo"
        ><.icon name="hero-camera" class="size-[18px]" /></button>
      </:header_controls>
      <div class="lesson-columns">
        <nav aria-label="Lesson units" class="stack">
          <h2 class="eyebrow">Units</h2><.form for={%{}} id="library-search" phx-change="filter">
            <.input
              name="search"
              value={@search}
              type="search"
              label="Find a unit"
              phx-debounce="200"
            />
          </.form><div id="library-texts" phx-update="stream" class="stack">
            <article :for={{id, unit} <- @streams.units} id={id}>
              <.link
                patch={~p"/lessons/#{unit.id}"}
                class={["unit-link", @lesson && @lesson.id == unit.id && "selected"]}
                aria-current={@lesson && @lesson.id == unit.id && "page"}
              ><strong>{unit.title}</strong><span>{Calendar.strftime(
                unit.inserted_at,
                "Imported %b %d"
              )}</span><StudyComponents.progress
                value={unit.position + 1}
                max={length(Reading.prepare(unit.body))}
                label={"Reading progress for #{unit.title}"}
              /></.link>
            </article>
          </div><button class="new-unit" phx-click="new"><.icon name="hero-plus" class="size-[18px]" />Import PDF, document or photo</button>
        </nav>
        <section class="stack">
          <%= if @lesson && !@import? do %>
            <div>
              <h1>{@lesson.title}</h1><p class="muted mt-2">
                {length(Reading.prepare(@lesson.body))} sentences · {Calendar.strftime(
                  @lesson.inserted_at,
                  "Imported %b %d"
                )}
              </p>
            </div>
            <section :if={@lesson.analysis["grammar"]} class="sentence-focus stack">
              <p class="eyebrow">Grammar of the unit</p><h2>
                {@lesson.analysis["grammar"]["title"]}
              </h2><p>{@lesson.analysis["grammar"]["body"]}</p><code class="pattern">{@lesson.analysis[
                "grammar"
              ]["pattern"]}</code>
            </section>
            <section class="card stack">
              <p class="eyebrow">Lesson vocabulary</p><div
                id="lesson-vocabulary"
                phx-update="stream"
                class="row wrap"
              >
                <button
                  :for={{id, word} <- @streams.vocabulary}
                  id={id}
                  class={["jar-word", "pos-#{word["category"]}"]}
                  phx-click="save-word"
                  phx-value-index={word["index"]}
                  title={"Save #{word["term"]}: #{word["meaning"]}"}
                >{word["term"]}</button>
              </div><button
                id="analyze-lesson"
                class="action self-start"
                phx-click="analyze"
                disabled={@busy}
              >{if @busy, do: "Preparing your guide…", else: "Build a grammar & vocabulary guide"}</button><p class="muted text-xs">
                The tutor reads up to the first 12,000 characters. Check its suggestions; it can make mistakes.
              </p>
            </section>
            <section class="stack">
              <p class="eyebrow">Texts in this unit</p><.link
                navigate={~p"/read/#{@lesson.id}"}
                class="library-row"
              ><div>
                <strong>Reading text</strong><p class="muted">
                  Pick up at sentence {@lesson.position + 1}
                </p>
              </div><strong>Read →</strong></.link><.link
                navigate={~p"/practice?#{%{text: @lesson.id}}"}
                class="library-row"
              ><div>
                <strong>Listening & speaking</strong><p class="muted">
                  Ready for dictation, shadowing, and rewriting
                </p>
              </div><strong>Practice →</strong></.link>
            </section>
          <% end %>
          <section :if={@import? || !@lesson} class="import-panel stack">
            <h1 class="!text-4xl">Bring your lesson along.</h1><p class="muted">
              Import a unit, a reading passage, or a clear photo of a page.
            </p><.form
              for={@form}
              id="material-form"
              phx-change="validate"
              phx-submit="import"
              phx-drop-target={@uploads.material.ref}
              class="stack"
            >
              <.input
                field={@form[:title]}
                label="Unit title"
                required
                maxlength="180"
                placeholder="Unit 3 · Present perfect"
              /><.input
                field={@form[:body]}
                type="textarea"
                label="Paste English text"
                maxlength="300000"
              /><label for={@uploads.material.ref} class="field-label">TXT, PDF, EPUB, DOCX, JPG or PNG · up to 10 MB</label><.live_file_input
                upload={@uploads.material}
                class="file-input"
              /><div :for={entry <- @uploads.material.entries} class="row">
                <span>{entry.client_name} · {entry.progress}%</span><button
                  class="text-link"
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                >Remove</button><p
                  :for={error <- upload_errors(@uploads.material, entry)}
                  class="notice-error"
                >
                  {error}
                </p>
              </div><p :for={error <- upload_errors(@uploads.material)} class="notice-error">
                {error}
              </p><.button phx-disable-with="Importing…">Save material</.button>
            </.form><p class="muted text-xs">
              PDFs need a text layer. Page photos use local OCR. Your originals are discarded after extraction.
            </p>
          </section>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
