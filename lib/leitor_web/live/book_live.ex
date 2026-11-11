defmodule LeitorWeb.BookLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Library

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    book = Library.get_book!(scope, id)
    depths = Map.new(book.toc["entries"] || [], &{&1["text_id"], &1["depth"]})
    chapters = scope |> Library.book_chapters(book) |> Enum.map(&Map.put(&1, :depth, Map.get(depths, &1.id, 0)))

    {:ok,
     assign(socket,
       page_title: book.title,
       book: book,
       chapters: chapters,
       continue_id: book.last_text_id || chapters |> List.first() |> then(&(&1 && &1.id))
     )}
  end

  @impl true
  def handle_event("delete", _, socket) do
    scope = socket.assigns.current_scope

    case Library.delete_book(scope, socket.assigns.book) do
      {:ok, _book} ->
        {:noreply, socket |> put_flash(:info, gettext("Book deleted.")) |> push_navigate(to: ~p"/pages")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Couldn't delete this book. Try again."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="library"
      class="workspace-page book-workspace"
    >
      <header class="workspace-heading">
        <div class="book-heading">
          <img
            :if={@book.cover_asset_id}
            id="book-cover"
            class="book-cover"
            src={~p"/book-assets/#{@book.cover_asset_id}"}
            alt={gettext("Cover of %{title}", title: @book.title)}
            decoding="async"
          />
          <div>
            <p class="workspace-eyebrow">{@book.author || gettext("Book")}</p>
            <h1 id="book-title">{@book.title}</h1>
            <p class="workspace-description">
              {ngettext("%{count} chapter", "%{count} chapters", length(@chapters))}
            </p>
          </div>
        </div>
        <div class="workspace-heading-actions">
          <.link
            :if={@continue_id}
            id="book-continue"
            navigate={~p"/pages/#{@continue_id}"}
            class="workspace-header-action workspace-header-primary"
          >
            <span>{if @book.last_text_id,
              do: gettext("Continue reading"),
              else: gettext("Start reading")}</span>
            <.icon name="lucide-thin-arrow-right" class="size-4" />
          </.link>
          <button
            id="book-delete"
            type="button"
            class="icon-button shelf-delete book-delete"
            aria-label={gettext("Delete %{title}", title: @book.title)}
            phx-click="delete"
            data-confirm={gettext("Delete this book and all of its chapters, notes and highlights?")}
          ><.icon name="lucide-thin-trash-2" class="size-4" /></button>
        </div>
      </header>
      <ol id="book-toc" class="book-toc" aria-label={gettext("Chapters")}>
        <li
          :for={chapter <- @chapters}
          id={"chapter-#{chapter.id}"}
          class={[
            "book-toc-item",
            "book-toc-depth-#{min(chapter.depth, 3)}",
            chapter.id == @continue_id && "is-current"
          ]}
        >
          <.link navigate={~p"/pages/#{chapter.id}"}>
            <span class="book-toc-number">{chapter.position + 1}</span>
            <span class="book-toc-title">{chapter.title}</span>
          </.link>
        </li>
      </ol>
      <footer class="workspace-footer">
        <.icon name="leitor-mark" class="size-5" /><p>{gettext("A little space. All yours.")}</p><.link navigate={
          ~p"/pages"
        }>{gettext("Back to your pages")} <.icon name="lucide-thin-arrow-right" class="size-3.5" /></.link>
      </footer>
    </Layouts.app>
    """
  end
end
