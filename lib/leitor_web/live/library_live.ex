defmodule LeitorWeb.LibraryLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Library
  alias Leitor.Library.Import

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Library.subscribe_texts(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(search: "", count: 0, form: to_form(%{"title" => "", "body" => ""}, as: "material"))
     |> stream(:texts, [])
     |> allow_upload(:material, accept: ~w(.txt .pdf .epub .docx), max_file_size: 10_000_000, max_entries: 1)}
  end

  @impl true
  def handle_params(_, _, socket), do: {:noreply, refresh(socket)}
  @impl true
  def handle_event("filter", %{"search" => search}, socket), do: {:noreply, socket |> assign(search: search) |> refresh()}

  def handle_event("delete", %{"id" => id}, socket) do
    text = Library.get_text!(socket.assigns.current_scope, id)

    case Library.delete_text(socket.assigns.current_scope, text) do
      {:ok, _} -> {:noreply, socket |> stream_delete(:texts, text) |> assign(count: max(socket.assigns.count - 1, 0))}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't delete this reading. Try again.")}
    end
  end

  def handle_event("validate", %{"material" => params}, socket),
    do: {:noreply, assign(socket, form: to_form(params, as: "material"))}

  def handle_event("cancel-upload", %{"ref" => ref}, socket), do: {:noreply, cancel_upload(socket, :material, ref)}

  def handle_event("import", %{"material" => params}, socket) do
    result =
      consume_uploaded_entries(socket, :material, fn %{path: path}, entry ->
        {:ok, Import.extract(path, entry.client_name)}
      end)

    body =
      case result do
        [{:ok, content}] -> {:ok, content}
        [{:error, reason}] -> {:error, reason}
        [] -> {:ok, params["body"] || ""}
      end

    save_material(socket, body, params)
  end

  defp save_material(socket, {:error, reason}, _params), do: {:noreply, put_flash(socket, :error, reason)}

  defp save_material(socket, {:ok, content}, params) do
    attrs = %{title: params["title"], body: content, position: 0, source: "import"}

    case Library.create_text(socket.assigns.current_scope, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(form: to_form(%{"title" => "", "body" => ""}, as: "material"))
         |> put_flash(:info, "Material saved. Ready to read and practice.")
         |> refresh()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "material", action: :insert))}
    end
  end

  @impl true
  def handle_info({event, %Library.Text{}}, socket) when event in [:created, :updated, :deleted],
    do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    texts =
      socket.assigns.current_scope
      |> Library.list_texts()
      |> Enum.filter(fn t ->
        String.contains?(String.downcase(t.title), String.downcase(socket.assigns.search))
      end)
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})

    socket
    |> assign(count: length(texts), page_title: "Your library")
    |> stream(:texts, texts, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="library"
    >
      <StudyComponents.page_heading
        eyebrow="Your own little bookshelf"
        title={@page_title}
        subtitle="Pick up where you left off. Every sentence is a small step forward."
      />
      <div class="grid-2">
        <section class="stack">
          <.form for={%{}} id="library-search" phx-change="filter">
            <.input
              name="search"
              value={@search}
              type="search"
              label="Find a text"
              placeholder="Search titles…"
              phx-debounce="200"
            />
          </.form>
          <div class="row between">
            <p class="eyebrow !mb-0">
              Saved readings
            </p><span class="badge">{@count}</span>
          </div>
          <div id="library-texts" phx-update="stream">
            <div id="library-empty" class="hidden only:block">
              <StudyComponents.empty_state
                title="A fresh page awaits."
                body="Import your first text or save a reading to see it here."
              />
            </div>
            <article :for={{id, text} <- @streams.texts} id={id} class="library-row">
              <.link navigate={~p"/read/#{text.id}"} class="flex-1"><h2 class="library-title">
                {text.title}
              </h2><p class="muted">
                Sentence {text.position + 1} · {text.source} · {Calendar.strftime(
                  text.updated_at,
                  "%b %d"
                )}
              </p></.link>
              <div class="row">
                <.link
                  navigate={~p"/practice?#{%{text: text.id}}"}
                  class="icon-button"
                  aria-label={"Practice #{text.title}"}
                ><.icon name="hero-play" class="size-4" /></.link><button
                  type="button"
                  class="icon-button"
                  aria-label={"Delete #{text.title}"}
                  phx-click="delete"
                  phx-value-id={text.id}
                  data-confirm="Delete this reading? Your vocabulary will be kept."
                ><.icon name="hero-trash" class="size-4" /></button>
              </div>
            </article>
          </div>
        </section>
        <section class="surface surface-lined stack self-start">
          <p class="eyebrow">Add to your shelf</p><h2>
            A new chapter.
          </h2>
          <.form
            for={@form}
            id="material-form"
            phx-change="validate"
            phx-submit="import"
            class="stack"
            phx-drop-target={@uploads.material.ref}
          >
            <.input
              field={@form[:title]}
              label="Title"
              placeholder="A name for your reading"
              required
              maxlength="180"
            />
            <.input
              field={@form[:body]}
              type="textarea"
              label="Paste English text"
              placeholder="Paste your text, or choose a document below…"
              maxlength="300000"
            />
            <div>
              <label for={@uploads.material.ref} class="field-label">Document · TXT, PDF, EPUB, DOCX</label><.live_file_input
                upload={@uploads.material}
                class="file-input"
              /><p :for={entry <- @uploads.material.entries} class="muted text-xs mt-2">
                {entry.client_name} · {entry.progress}%
                <span :for={error <- upload_errors(@uploads.material, entry)} class="notice-error">{error}</span>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  class="text-link"
                >Remove</button>
              </p><p :for={error <- upload_errors(@uploads.material)} class="notice-error">{error}</p>
            </div>
            <.button id="save-material" variant="primary" phx-disable-with="Saving…">Save material
            <span aria-hidden="true">→</span></.button>
          </.form>
          <p class="footer-note">
            Your materials are private. PDFs need a text layer; scanned images can be pasted after OCR.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
