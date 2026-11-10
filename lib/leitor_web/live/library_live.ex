defmodule LeitorWeb.LibraryLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Library
  alias Leitor.Library.Book
  alias Leitor.Library.Epub
  alias Leitor.Library.Import

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Library.subscribe_texts(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(
       search: "",
       source: "all",
       sort: "recent",
       import_open: false,
       count: 0,
       form: to_form(%{"body" => ""}, as: "material")
     )
     |> stream(:texts, [])
     |> allow_upload(:material,
       accept: ~w(.md .markdown .txt .pdf .epub .docx),
       max_file_size: 10_000_000,
       max_entries: 1
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    source = if params["source"] in ~w(page import), do: params["source"], else: "all"
    sort = if params["sort"] == "title", do: "title", else: "recent"
    search = if is_binary(params["search"]), do: String.slice(params["search"], 0, 200), else: ""
    {:noreply, socket |> assign(source: source, sort: sort, search: search) |> refresh()}
  end

  @impl true
  def handle_event("filter", %{"search" => search}, socket),
    do:
      {:noreply,
       push_patch(socket, to: library_path(String.slice(search, 0, 200), socket.assigns.source, socket.assigns.sort))}

  def handle_event("source", %{"source" => source}, socket) when source in ~w(all page import),
    do: {:noreply, push_patch(socket, to: library_path(socket.assigns.search, source, socket.assigns.sort))}

  def handle_event("sort", %{"sort" => sort}, socket) when sort in ~w(recent title),
    do: {:noreply, push_patch(socket, to: library_path(socket.assigns.search, socket.assigns.source, sort))}

  def handle_event("open-import", _, socket), do: {:noreply, assign(socket, import_open: true)}

  def handle_event("close-import", _, socket) do
    socket = Enum.reduce(socket.assigns.uploads.material.entries, socket, &cancel_upload(&2, :material, &1.ref))
    {:noreply, assign(socket, import_open: false)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    text = Library.get_text!(socket.assigns.current_scope, id)

    case Library.delete_text(socket.assigns.current_scope, text) do
      {:ok, _} -> {:noreply, refresh(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Couldn't delete this reading. Try again."))}
    end
  end

  def handle_event("delete-book", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Library.delete_book(scope, Library.get_book!(scope, id)) do
      {:ok, _} -> {:noreply, refresh(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Couldn't delete this book. Try again."))}
    end
  end

  def handle_event("validate", %{"material" => params}, socket),
    do: {:noreply, assign(socket, form: to_form(Map.take(params, ["body"]), as: "material"))}

  def handle_event("cancel-upload", %{"ref" => ref}, socket), do: {:noreply, cancel_upload(socket, :material, ref)}

  def handle_event("import", %{"material" => params}, socket) do
    result =
      consume_uploaded_entries(socket, :material, fn %{path: path}, entry ->
        {:ok, read_upload(path, entry.client_name)}
      end)

    body =
      case result do
        [{:ok, content}] ->
          {:ok, content}

        [{:error, reason}] ->
          {:error, reason}

        [] ->
          content = params["body"] || ""
          {:ok, {:text, %{title: Import.title(content), body: content}}}
      end

    save_material(socket, body)
  end

  defp save_material(socket, {:error, reason}), do: {:noreply, put_flash(socket, :error, reason)}

  defp save_material(socket, {:ok, {:book, book}}) do
    case Library.create_book(socket.assigns.current_scope, book) do
      {:ok, _book} ->
        {:noreply,
         socket
         |> assign(import_open: false, form: to_form(%{"body" => ""}, as: "material"))
         |> put_flash(:info, gettext("Book saved. Ready to read."))
         |> push_navigate(to: ~p"/pages/#{hd(book.chapters).id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("We couldn't save this book. Check its chapters and try again."))}
    end
  end

  defp save_material(socket, {:ok, {:text, %{title: title, body: content}}}) do
    attrs = %{title: title, body: content, position: 0, source: "import"}

    case Library.create_text(socket.assigns.current_scope, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(import_open: false, form: to_form(%{"body" => ""}, as: "material"))
         |> put_flash(:info, "Page saved. Ready to read.")
         |> push_patch(to: ~p"/pages")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "material", action: :insert))}
    end
  end

  # An EPUB becomes a book with chapters; everything else is read as a single text.
  defp read_upload(path, name) do
    if String.downcase(Path.extname(name)) == ".epub" do
      with {:ok, book} <- Epub.extract_book(path), do: {:ok, {:book, book}}
    else
      with {:ok, document} <- Import.extract_document(path, name), do: {:ok, {:text, document}}
    end
  end

  @impl true
  def handle_info({event, %Library.Text{}}, socket) when event in [:created, :updated, :deleted],
    do: {:noreply, refresh(socket)}

  def handle_info({event, %Book{}}, socket) when event in [:book_created, :book_deleted], do: {:noreply, refresh(socket)}

  defp library_path(search, source, sort), do: ~p"/pages?#{%{search: search, source: source, sort: sort}}"

  defp refresh(socket) do
    scope = socket.assigns.current_scope
    items = Library.list_texts(scope) ++ Library.list_books(scope)
    source = socket.assigns.source
    search = String.downcase(socket.assigns.search)

    shown =
      items
      |> Enum.filter(&(matches_search?(&1, search) and matches_source?(&1, source)))
      |> sort_items(socket.assigns.sort)

    socket
    |> assign(count: length(shown), all_count: length(items), page_title: gettext("Your pages"))
    |> stream(:texts, shown, reset: true)
  end

  defp matches_search?(item, search),
    do: String.contains?(String.downcase(item.title <> " " <> (Map.get(item, :author) || "")), search)

  defp matches_source?(_item, "all"), do: true
  defp matches_source?(%Book{}, source), do: source == "import"
  defp matches_source?(text, "page"), do: text.source == "page"
  defp matches_source?(text, "import"), do: text.source != "page"

  defp sort_items(items, "title"), do: Enum.sort_by(items, &{String.downcase(&1.title), &1.id})

  defp sort_items(items, "recent"),
    do: Enum.sort_by(items, &{DateTime.to_unix(&1.updated_at, :microsecond), &1.id}, :desc)

  defp book_path(%Book{last_text_id: last, first_text_id: first}), do: ~p"/pages/#{last || first}"

  defp preview(body) do
    body
    |> String.slice(0, 800)
    |> String.replace(~r/[#*_>`~\[\]]/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, 190)
  end

  defp reading_time(body) do
    if String.trim(body) == "",
      do: gettext("A blank page"),
      else: gettext("%{minutes} min read", minutes: max(div(length(String.split(body)) + 219, 220), 1))
  end

  defp upload_error(:too_large), do: "Choose a file smaller than 10 MB."
  defp upload_error(:not_accepted), do: "Choose a Markdown, TXT, PDF, EPUB or DOCX file."
  defp upload_error(:too_many_files), do: "Import one document at a time."
  defp upload_error(:external_client_failure), do: "The upload failed. Remove the file and try again."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="library"
      class="workspace-page pages-workspace"
    >
      <:tabs>
        <div class="header-context-tabs shelf-sources" role="group" aria-label={gettext("Page types")}>
          <button
            :for={
              {source, label} <- [
                {"all", "All pages"},
                {"page", "Written here"},
                {"import", "Imported"}
              ]
            }
            id={"pages-source-#{source}"}
            type="button"
            phx-click="source"
            phx-value-source={source}
            aria-pressed={to_string(@source == source)}
          >{t(label)}</button>
        </div>
      </:tabs>
      <:tools>
        <Layouts.workspace_filters active={@search != "" || @sort != "recent"}>
          <p class="workspace-submenu-heading">{gettext("Find a page")}</p>
          <.form for={%{}} id="library-search" phx-change="filter">
            <.input
              id="library-query"
              name="search"
              value={@search}
              type="search"
              aria-label={gettext("Find a text")}
              placeholder={gettext("Find a title…")}
              phx-debounce="250"
              maxlength="200"
            />
          </.form>
          <.form for={%{}} id="library-sort" phx-change="sort">
            <.input
              id="library-order"
              name="sort"
              value={@sort}
              type="select"
              label={gettext("Order pages")}
              options={[{gettext("Recently updated"), "recent"}, {gettext("Title A–Z"), "title"}]}
            />
          </.form>
        </Layouts.workspace_filters>
        <.popover
          id="page-create"
          label={gettext("Add page")}
          trigger_class="workspace-header-action workspace-header-primary page-create-trigger"
          panel_class="dropdown-menu"
          menu
        >
          <:trigger>
            <.icon name="lucide-thin-plus" class="size-4" /><span>{gettext("Add page")}</span>
            <.icon name="lucide-thin-chevron-down" class="page-create-chevron size-3.5" />
          </:trigger>
          <.dropdown_item
            id="new-free-page"
            navigate={~p"/pages/new"}
            label={gettext("Blank page")}
            icon="lucide-thin-pen-line"
          />
          <button
            id="open-page-import"
            type="button"
            class="dropdown-item"
            role="menuitem"
            tabindex="-1"
            phx-click={
              JS.push_focus(to: "#page-create-trigger")
              |> JS.remove_attribute("open", to: "#page-create")
              |> JS.push("open-import")
            }
          ><.icon name="lucide-thin-download" class="size-4" /><span class="dropdown-item-label">{gettext(
            "Import text"
          )}</span></button>
        </.popover>
      </:tools>
      <header class="workspace-heading">
        <div>
          <p class="workspace-eyebrow">{gettext("Your own reading room")}</p><h1>
            {gettext("Your pages.")}
          </h1>
          <p class="workspace-description">
            {gettext("A fresh page. A familiar passage. A little more to discover.")}
          </p>
        </div>
      </header>
      <div class="shelf-results-heading">
        <p>
          <span>{@count}</span> {if @count == 1, do: gettext("page"), else: gettext("pages")}{if @count !=
                                                                                                   @all_count,
                                                                                                 do:
                                                                                                   gettext(
                                                                                                     " of %{count}",
                                                                                                     count:
                                                                                                       @all_count
                                                                                                   )}
        </p><span>{gettext("Something worth coming back to.")}</span>
      </div>
      <div id="library-texts" phx-update="stream" class="shelf-grid">
        <div id="library-empty" class="hidden only:flex workspace-empty">
          <.icon name="lucide-thin-book-open" class="size-8" />
          <h2>
            {if @all_count == 0,
              do: gettext("Your first page starts here."),
              else: gettext("No pages found.")}
          </h2>
          <p>
            {if @all_count == 0,
              do: gettext("Bring a text you love, or start with a thought of your own."),
              else: gettext("Try another title or choose a different page type.")}
          </p>
          <.link navigate={~p"/pages/new"} class="text-link">{gettext("Open a new page")}
          <.icon name="lucide-thin-arrow-right" class="size-4" /></.link>
        </div>
        <article :for={{id, item} <- @streams.texts} id={id} class="shelf-card">
          <%= if match?(%Book{}, item) do %>
            <div class="shelf-card-top">
              <span><.icon name="lucide-thin-book-open" class="size-3.5" /> {gettext("Book")}</span>
              <button
                type="button"
                class="icon-button shelf-delete"
                aria-label={gettext("Delete %{title}", title: item.title)}
                phx-click="delete-book"
                phx-value-id={item.id}
                data-confirm={
                  gettext("Delete this book and all of its chapters, notes and highlights?")
                }
              ><.icon name="lucide-thin-trash-2" class="size-4" /></button>
            </div>
            <.link navigate={book_path(item)} class="shelf-card-reading" id={"book-#{item.id}-open"}>
              <h2>{item.title}</h2>
              <p :if={item.author}>{item.author}</p>
              <div class="shelf-card-footer">
                <span>{ngettext("%{count} chapter", "%{count} chapters", item.chapter_count)}</span><span>{LeitorWeb.I18n.date(
                  item.updated_at
                )}
                <.icon name="lucide-thin-arrow-up-right" class="size-4" /></span>
              </div>
            </.link>
          <% else %>
            <div class="shelf-card-top">
              <span><.icon
                name={
                  if item.source == "page", do: "lucide-thin-pen-line", else: "lucide-thin-book-open"
                }
                class="size-3.5"
              /> {if item.source == "page",
                do: gettext("Your writing"),
                else: gettext("From your shelf")}</span>
              <button
                type="button"
                class="icon-button shelf-delete"
                aria-label={gettext("Delete %{title}", title: item.title)}
                phx-click="delete"
                phx-value-id={item.id}
                data-confirm={gettext("Delete this reading? Your vocabulary will be kept.")}
              ><.icon name="lucide-thin-trash-2" class="size-4" /></button>
            </div>
            <.link navigate={~p"/pages/#{item.id}"} class="shelf-card-reading">
              <h2>{item.title}</h2><p>
                {if String.trim(item.body) == "",
                  do: gettext("An open page, waiting for your next thought."),
                  else: preview(item.body)}
              </p>
              <div class="shelf-card-footer">
                <span>{reading_time(item.body)}</span><span>{LeitorWeb.I18n.date(item.updated_at)}
                <.icon name="lucide-thin-arrow-up-right" class="size-4" /></span>
              </div>
            </.link>
          <% end %>
        </article>
      </div>
      <footer class="workspace-footer">
        <.icon name="leitor-mark" class="size-5" /><p>{gettext("A little space. All yours.")}</p><.link navigate={
          ~p"/notebook"
        }>{gettext("Visit your notebook")} <.icon name="lucide-thin-arrow-right" class="size-3.5" /></.link>
      </footer>
      <StudyComponents.dialog
        :if={@import_open}
        id="page-import-dialog"
        title={gettext("A new chapter.")}
        on_close={JS.push("close-import")}
      >
        <p class="import-description">
          {gettext("Paste a text or bring a document. We’ll find its title.")}
        </p>
        <.form
          for={@form}
          id="material-form"
          phx-change="validate"
          phx-submit="import"
          class="import-form"
          phx-drop-target={@uploads.material.ref}
        >
          <div class="import-content">
            <.input
              field={@form[:body]}
              type="textarea"
              aria-label={gettext("Text to import")}
              placeholder={
                gettext("Paste your text or Markdown here…\n\n    You can also drop a document.")
              }
              readonly={@uploads.material.entries != []}
              maxlength="300000"
            />
            <div class="import-attachments">
              <label class="import-attach" for={@uploads.material.ref}>
                <.icon name="lucide-thin-plus" class="size-4" /> {gettext("Choose a file")}
                <.live_file_input upload={@uploads.material} class="sr-only" />
              </label>
              <span class="import-formats">{gettext("MD, TXT, PDF, EPUB, DOCX")}</span>
            </div>
            <div :for={entry <- @uploads.material.entries} class="import-file">
              <.icon name="lucide-thin-book-open" class="size-4" />
              <span>{entry.client_name}</span>
              <small>{entry.progress}%</small>
              <button
                type="button"
                class="icon-button"
                aria-label={gettext("Remove %{filename}", filename: entry.client_name)}
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
              ><.icon name="lucide-thin-x" class="size-3.5" /></button>
              <p :for={error <- upload_errors(@uploads.material, entry)} class="notice-error">
                {t(upload_error(error))}
              </p>
            </div>
            <p :for={error <- upload_errors(@uploads.material)} class="notice-error">
              {t(upload_error(error))}
            </p>
          </div>
          <div class="import-footer">
            <p>{gettext("Private to you · Up to 10 MB")}</p>
            <.button id="save-material" variant="primary" phx-disable-with={gettext("Importing…")}>{gettext(
              "Import text"
            )}
            <.icon name="lucide-thin-arrow-right" class="size-4" /></.button>
          </div>
        </.form>
      </StudyComponents.dialog>
    </Layouts.app>
    """
  end
end
