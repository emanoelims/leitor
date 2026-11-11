defmodule LeitorWeb.NotebookLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning
  alias Leitor.PageDocument
  alias Leitor.Pages
  alias LeitorWeb.NotebookComponents

  @kinds ~w(all highlight note definition answer)

  @word_categories ~w(all known noun verb adj adv pron prep expression error word)

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Learning.subscribe_entries(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(selected: nil, word_form: nil)
     |> stream(:entries, [])
     |> stream(:jars, [])}
  end

  @impl true
  def handle_params(params, _, socket) do
    filters = normalize_filters(params)
    view = if params["view"] == "words", do: "words", else: "notes"
    word_filter = if params["jar"] in @word_categories, do: params["jar"], else: "all"
    word_search = if is_binary(params["q"]), do: params["q"] |> String.slice(0, 200) |> String.trim(), else: ""
    result = Pages.notebook(socket.assigns.current_scope, filters, page_number(params["page"]))
    sources = Pages.notebook_sources(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(
       page_title: gettext("Notebook"),
       selected: nil,
       word_form: nil,
       view: view,
       word_filter: word_filter,
       word_search: word_search,
       hide_empty: params["filled"] == "true",
       word_search_form: to_form(%{"search" => word_search}, as: "words"),
       filters: filters,
       page: result.page,
       total: result.total,
       page_count: max(div(result.total + result.per_page - 1, result.per_page), 1),
       shared_sources: Leitor.Sharing.links_for(socket.assigns.current_scope, Enum.map(sources, & &1.id)),
       sources: Enum.map(sources, &{&1.title, &1.id}),
       filter_form: to_form(%{"search" => filters.search, "text_id" => filters.text_id || ""}, as: "filters")
     )
     |> stream(:entries, result.entries, reset: true)
     |> refresh_words()}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = normalize_filters(Map.put(params, "kind", socket.assigns.filters.kind))
    {:noreply, push_patch(socket, to: notebook_path(filters, 1))}
  end

  def handle_event("kind", %{"kind" => kind}, socket) when kind in @kinds do
    {:noreply, push_patch(socket, to: notebook_path(%{socket.assigns.filters | kind: kind}, 1))}
  end

  def handle_event("kind", _, socket), do: {:noreply, socket}
  def handle_event("clear", _, socket), do: {:noreply, push_patch(socket, to: ~p"/notebook")}

  def handle_event("word-category", %{"category" => category}, socket) when category in @word_categories,
    do: {:noreply, push_patch(socket, to: words_path(category, socket.assigns.word_search, socket.assigns.hide_empty))}

  def handle_event("word-search", %{"words" => %{"search" => search}}, socket),
    do:
      {:noreply,
       push_patch(socket,
         to: words_path(socket.assigns.word_filter, String.slice(search, 0, 200), socket.assigns.hide_empty)
       )}

  def handle_event("hide-empty", _, socket),
    do:
      {:noreply,
       push_patch(socket,
         to: words_path(socket.assigns.word_filter, socket.assigns.word_search, !socket.assigns.hide_empty)
       )}

  def handle_event("open", %{"id" => id}, socket) do
    entry = Learning.get_entry!(socket.assigns.current_scope, id)

    {:noreply,
     assign(socket,
       selected: entry,
       word_form: to_form(Learning.change_entry(socket.assigns.current_scope, entry), as: "entry")
     )}
  end

  def handle_event("close", _, socket), do: {:noreply, assign(socket, selected: nil, word_form: nil)}

  def handle_event("known", %{"id" => id}, socket) do
    entry = Learning.get_entry!(socket.assigns.current_scope, id)
    status = if entry.status == "known", do: "learning", else: "known"

    case Learning.update_entry(socket.assigns.current_scope, entry, %{status: status}) do
      {:ok, _} -> {:noreply, socket |> assign(selected: nil, word_form: nil) |> refresh_words()}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Couldn't update this word. Try again."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    entry = Learning.get_entry!(socket.assigns.current_scope, id)

    case Learning.delete_entry(socket.assigns.current_scope, entry) do
      {:ok, _} -> {:noreply, socket |> assign(selected: nil, word_form: nil) |> refresh_words()}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Couldn't remove this word. Try again."))}
    end
  end

  def handle_event("edit", %{"entry" => attrs}, %{assigns: %{selected: %Learning.Entry{id: id}}} = socket) do
    entry = Learning.get_entry!(socket.assigns.current_scope, id)

    case Learning.update_entry(socket.assigns.current_scope, entry, Map.take(attrs, ["meaning", "category"])) do
      {:ok, _} -> {:noreply, socket |> assign(selected: nil, word_form: nil) |> refresh_words()}
      {:error, changeset} -> {:noreply, assign(socket, word_form: to_form(changeset, as: "entry"))}
    end
  end

  @impl true
  def handle_info({event, %Learning.Entry{id: id}}, socket) when event in [:created, :updated, :deleted] do
    socket =
      case {event, socket.assigns.selected} do
        {:deleted, %Learning.Entry{id: ^id}} -> assign(socket, selected: nil, word_form: nil)
        _ -> socket
      end

    {:noreply, refresh_words(socket)}
  end

  defp words_path(category, search, filled),
    do: ~p"/notebook?#{%{view: "words", jar: category, q: search, filled: to_string(filled)}}"

  defp refresh_words(socket) do
    entries = Learning.vocabulary(socket.assigns.current_scope, socket.assigns.word_filter, socket.assigns.word_search)

    definitions = [
      {"noun", "Nouns", "People, places, things"},
      {"verb", "Verbs", "Actions and states"},
      {"adj", "Adjectives", "Qualities and descriptions"},
      {"adv", "Adverbs", "How, when, how often"},
      {"pron", "Pronouns", "Words that stand in"},
      {"prep", "Prepositions", "Relationships and positions"},
      {"expression", "Expressions", "Words that work together"},
      {"error", "My mistakes", "Corrections worth revisiting"},
      {"word", "Other words", "The rest of your discoveries"}
    ]

    grouped = Enum.group_by(entries, &jar_category(&1.category))

    jars =
      for {category, label, hint} <- definitions,
          words = Map.get(grouped, category, []),
          not socket.assigns.hide_empty or words != [],
          socket.assigns.word_filter in ["all", "known"] or category == socket.assigns.word_filter do
        %{id: category, category: category, label: label, hint: hint, words: words, count: length(words)}
      end

    socket |> assign(count: length(entries)) |> stream(:jars, Enum.sort_by(jars, &(&1.count == 0)), reset: true)
  end

  defp jar_category("aux"), do: "verb"
  defp jar_category("proper"), do: "noun"
  defp jar_category(category) when category in ~w(noun verb adj adv pron prep expression error), do: category
  defp jar_category(_), do: "word"

  defp normalize_filters(params) do
    search = if is_binary(params["search"]), do: params["search"] |> String.slice(0, 200) |> String.trim(), else: ""
    kind = if params["kind"] in @kinds, do: params["kind"], else: "all"

    text_id =
      case Ecto.UUID.cast(params["text_id"]) do
        {:ok, id} -> id
        :error -> nil
      end

    %{search: search, kind: kind, text_id: text_id}
  end

  defp page_number(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number > 0 and number <= 1_000_000 -> number
      _ -> 1
    end
  end

  defp page_number(_), do: 1

  defp notebook_path(filters, page) do
    ~p"/notebook?#{%{search: filters.search, kind: filters.kind, text_id: filters.text_id || "", page: page}}"
  end

  defp entry_title("highlight"), do: "Highlight"
  defp entry_title("note"), do: "Note"
  defp entry_title("definition"), do: "Definition"
  defp entry_title("answer"), do: "Question"
  defp answer_html(body), do: Phoenix.HTML.raw(PageDocument.render_answer(body))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="notebook"
      context_title="Notebook"
      class="workspace-page notebook-workspace"
    >
      <:tabs>
        <nav class="header-context-tabs notebook-views" aria-label={gettext("Notebook sections")}>
          <.link
            id="notebook-notes-tab"
            patch={~p"/notebook"}
            aria-current={@view == "notes" && "page"}
          ><.icon
            name="lucide-thin-notebook-pen"
            class="size-4"
          /> {gettext("Notes & ideas")}</.link>
          <.link
            id="notebook-words-tab"
            patch={~p"/notebook?view=words"}
            aria-current={@view == "words" && "page"}
          ><.icon name="lucide-thin-flask-conical" class="size-4" /> {gettext("Word jars")}</.link>
        </nav>
      </:tabs>
      <:tools>
        <Layouts.workspace_filters active={
          if @view == "words",
            do: @word_filter != "all" || @word_search != "" || @hide_empty,
            else: @filters.search != "" || @filters.kind != "all" || not is_nil(@filters.text_id)
        }>
          <%= if @view == "words" do %>
            <NotebookComponents.word_filters
              word_filter={@word_filter}
              word_search_form={@word_search_form}
              hide_empty={@hide_empty}
            />
          <% else %>
            <p class="workspace-submenu-heading">{gettext("Find annotations")}</p>

            <.form
              for={@filter_form}
              id="notebook-search"
              phx-change="filter"
              class="workspace-filter-form"
            >
              <.input
                field={@filter_form[:search]}
                type="search"
                label={gettext("Search your notebook")}
                placeholder={gettext("A word, a thought, a page title…")}
                phx-debounce="250"
                maxlength="200"
              />
              <.input
                field={@filter_form[:text_id]}
                type="select"
                label={gettext("Source page")}
                options={[{gettext("All pages"), ""} | @sources]}
              />
            </.form>
            <div
              class="workspace-filter-choices"
              role="group"
              aria-label={gettext("Annotation types")}
            >
              <button
                :for={
                  {kind, label} <- [
                    {"all", "All"},
                    {"note", "Notes"},
                    {"definition", "Definitions"},
                    {"answer", "Questions"},
                    {"highlight", "Highlights"}
                  ]
                }
                id={"global-notebook-filter-#{kind}"}
                type="button"
                class={[@filters.kind == kind && "selected"]}
                phx-click="kind"
                phx-value-kind={kind}
                aria-pressed={to_string(@filters.kind == kind)}
              >{t(label)}</button>
            </div>
            <button
              :if={@filters.search != "" || @filters.kind != "all" || @filters.text_id}
              id="notebook-clear"
              type="button"
              class="text-link"
              phx-click="clear"
            >{gettext("Reset filters")}</button>
          <% end %>
        </Layouts.workspace_filters>
      </:tools>
      <header class="workspace-heading">
        <div>
          <p class="workspace-eyebrow">{gettext("The things you keep")}</p><h1>
            {gettext("Your notebook.")}
          </h1>
          <p class="workspace-description">
            {gettext("A thought in the margin. A word made yours. All together, right here.")}
          </p>
        </div>
        <.link navigate={~p"/pages"} class="workspace-quiet-action">{gettext("Back to your pages")}
        <.icon name="lucide-thin-arrow-up-right" class="size-4" /></.link>
      </header>
      <%= if @view == "words" do %>
        <NotebookComponents.word_jars
          streams={@streams}
          word_search={@word_search}
          word_form={@word_form}
          hide_empty={@hide_empty}
          count={@count}
          selected={@selected}
        />
      <% else %>
        <div class="notebook-results-heading">
          <p id="notebook-result-count" class="eyebrow">
            {ngettext("%{count} saved entry", "%{count} saved entries", @total)}
          </p>
        </div>
        <div id="global-notebook-entries" phx-update="stream" class="notebook-entry-list">
          <div id="global-notebook-empty" class="hidden only:block notebook-global-empty">
            <.icon name="lucide-notebook-pen" class="size-8" />
            <h2>
              {if @filters.search != "" || @filters.kind != "all" || @filters.text_id,
                do: gettext("No annotations found"),
                else: gettext("A place for your thoughts")}
            </h2>
            <p>
              {gettext(
                "Select a passage on any page and keep a note. Your annotations will be gathered here."
              )}
            </p>
            <.link navigate={~p"/pages"} class="text-link">{gettext("Find a page to read")}
            <.icon name="lucide-arrow-right" class="size-4" /></.link>
          </div>
          <article :for={{id, entry} <- @streams.entries} id={id} class="notebook-entry">
            <header class="notebook-entry-heading">
              <span class="notebook-entry-kind">{t(entry_title(entry.kind))}</span>
              <.link
                id={"notebook-source-#{entry.id}"}
                navigate={
                  if token =
                       entry.text.user_id != @current_scope.user.id && @shared_sources[entry.text_id],
                     do: ~p"/s/#{token}?#{[mark: entry.id]}",
                     else: ~p"/pages/#{entry.text_id}?#{[mark: entry.id]}"
                }
                class="notebook-source-link"
                title={gettext("Open the source passage")}
              ><span>{entry.text.title}</span><.icon name="lucide-arrow-up-right" class="size-4" /></.link>
            </header>
            <blockquote>{entry.quote}</blockquote>
            <h3 :if={entry.question && entry.question != ""}>{entry.question}</h3>
            <div :if={entry.body != ""} class="page-answer notebook-entry-body">
              {answer_html(entry.body)}
            </div>
            <details :if={entry.replies != []} class="notebook-entry-replies">
              <summary>
                {length(entry.replies)} {if length(entry.replies) == 1,
                  do: gettext("follow-up"),
                  else: gettext("follow-ups")}
              </summary>
              <div
                :for={reply <- entry.replies}
                id={"#{id}-reply-#{reply.id}"}
                class="page-follow-turn"
              >
                <h4>{reply.question}</h4><div class="page-answer">{answer_html(reply.body)}</div>
              </div>
            </details>
          </article>
        </div>
        <nav :if={@page_count > 1} class="notebook-pagination" aria-label={gettext("Notebook pages")}>
          <.link
            :if={@page > 1}
            id="notebook-previous"
            patch={notebook_path(@filters, @page - 1)}
            class="text-link"
          >{gettext("Previous")}</.link>
          <span>{gettext("Page")} {@page} {gettext("of")} {@page_count}</span>
          <.link
            :if={@page < @page_count}
            id="notebook-next"
            patch={notebook_path(@filters, @page + 1)}
            class="text-link"
          >{gettext("Next")}</.link>
        </nav>
      <% end %>
    </Layouts.app>
    """
  end
end
