defmodule LeitorWeb.VocabularyLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Learning.subscribe_entries(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(page_title: "Your words", filter: "all", selected: nil, count: 0, hide_empty: false)
     |> stream(:jars, [])
     |> refresh()}
  end

  @impl true
  def handle_event("hide-empty", _, socket),
    do: {:noreply, socket |> assign(hide_empty: !socket.assigns.hide_empty) |> refresh()}

  def handle_event("filter", %{"category" => category}, socket),
    do: {:noreply, socket |> assign(filter: category, selected: nil) |> refresh()}

  def handle_event("open", %{"id" => id}, socket),
    do: {:noreply, assign(socket, selected: Learning.get_entry!(socket.assigns.current_scope, id))}

  def handle_event("close", _, socket), do: {:noreply, assign(socket, selected: nil)}

  def handle_event("known", %{"id" => id}, socket) do
    entry = Learning.get_entry!(socket.assigns.current_scope, id)

    {:ok, _} =
      Learning.update_entry(socket.assigns.current_scope, entry, %{
        status: if(entry.status == "known", do: "learning", else: "known")
      })

    {:noreply, socket |> assign(selected: nil) |> refresh()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    entry = Learning.get_entry!(socket.assigns.current_scope, id)
    {:ok, _} = Learning.delete_entry(socket.assigns.current_scope, entry)
    {:noreply, socket |> assign(selected: nil) |> refresh()}
  end

  def handle_event("edit", %{"entry" => attrs}, socket) do
    entry = Learning.get_entry!(socket.assigns.current_scope, socket.assigns.selected.id)

    case Learning.update_entry(socket.assigns.current_scope, entry, Map.take(attrs, ["meaning", "category"])) do
      {:ok, _} -> {:noreply, socket |> assign(selected: nil) |> refresh()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Add a meaning before saving.")}
    end
  end

  @impl true
  def handle_info({event, %Learning.Entry{}}, socket) when event in [:created, :updated, :deleted],
    do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    entries = Learning.vocabulary(socket.assigns.current_scope, socket.assigns.filter)

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

    grouped = Enum.group_by(entries, fn entry -> jar_category(entry.category) end)

    jars =
      for {category, label, hint} <- definitions,
          words = Map.get(grouped, category, []),
          not socket.assigns.hide_empty or words != [],
          socket.assigns.filter in ["all", "known"] or category == socket.assigns.filter do
        %{id: category, category: category, label: label, hint: hint, words: words, count: length(words)}
      end

    socket |> assign(count: length(entries)) |> stream(:jars, jars, reset: true)
  end

  defp jar_category("aux"), do: "verb"
  defp jar_category("proper"), do: "noun"
  defp jar_category(category) when category in ~w(noun verb adj adv pron prep expression error), do: category
  defp jar_category(_), do: "word"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="vocabulary"
      context_detail={"#{@count} collected words"}
    >
      <:header_controls>
        <button
          class={["layer-button", @hide_empty && "active"]}
          phx-click="hide-empty"
          aria-pressed={@hide_empty}
          aria-label="Hide empty jars"
        ><.icon name="hero-funnel" class="size-[18px]" /><span :if={@hide_empty}>Only filled jars</span></button><.link
          navigate={~p"/review"}
          class="icon-button"
          aria-label="Review words"
        ><.icon name="hero-arrow-path" class="size-[18px]" /></.link>
      </:header_controls>
      <StudyComponents.page_heading
        title="Word jars"
        subtitle="Your 200 most recently updated words, grouped by grammar. Tap a word to revisit its context."
      >
        <:actions>
          <.link navigate={~p"/review"} class="action action-primary"><.icon
            name="hero-arrow-path"
            class="size-4"
          />Review words</.link>
        </:actions>
      </StudyComponents.page_heading>
      <div class="practice-tabs" aria-label="Vocabulary filters">
        <button
          :for={
            {value, label} <- [
              {"all", "All words"},
              {"noun", "Nouns"},
              {"verb", "Verbs"},
              {"adj", "Adjectives"},
              {"adv", "Adverbs"},
              {"expression", "Expressions"},
              {"error", "My mistakes"},
              {"known", "Already known"}
            ]
          }
          id={"filter-#{value}"}
          type="button"
          class={["action action-small", @filter == value && "active"]}
          aria-pressed={@filter == value}
          phx-click="filter"
          phx-value-category={value}
        >{label}</button>
      </div>
      <div class="row between mb-6">
        <p class="eyebrow !mb-0">{@count} collected {if @count == 1, do: "word", else: "words"}</p><.link
          navigate={~p"/read"}
          class="text-link text-sm"
        >Find something new →</.link>
      </div>
      <div id="vocabulary-entries" phx-update="stream" class="jar-grid">
        <section :for={{id, jar} <- @streams.jars} id={id} class="jar-card" aria-label={jar.label}>
          <div class="row between">
            <div class="row">
              <span class="jar-icon" aria-hidden="true"><i class={"pos-#{jar.category}"}></i></span><div>
                <h2>{jar.label}</h2><p class="muted text-[13px]">{jar.hint}</p>
              </div>
            </div><span class="jar-count">{jar.count}</span>
          </div>
          <div class="row wrap jar-words">
            <button
              :for={entry <- jar.words}
              id={"open-#{entry.id}"}
              class={["jar-word", "pos-#{jar.category}"]}
              phx-click={JS.push_focus() |> JS.push("open")}
              phx-value-id={entry.id}
            >{entry.term}<span>{String.slice(entry.meaning, 0, 45)}</span><span
              :if={entry.status == "known"}
              aria-label="Known"
            >✓</span></button>
          </div>
          <p :if={jar.words == []} class="muted text-sm mt-auto">Empty for now.</p>
        </section>
      </div>
      <StudyComponents.dialog
        :if={@selected}
        id="vocabulary-dialog"
        title={@selected.term}
        on_close={JS.push("close")}
      >
        <p class="muted mb-5">{@selected.context}</p>
        <.form
          for={
            to_form(%{"meaning" => @selected.meaning, "category" => @selected.category}, as: "entry")
          }
          id="entry-edit"
          phx-submit="edit"
        >
          <.input
            name="entry[meaning]"
            value={@selected.meaning}
            label="Meaning / learning note"
            required
            maxlength="2000"
          />
          <.input
            name="entry[category]"
            value={@selected.category}
            type="select"
            label="Jar"
            options={~w(word noun verb aux adj adv pron prep det conj proper expression error)}
          />
          <.button variant="primary">Save changes</.button>
        </.form>
        <div class="row mt-5">
          <button type="button" class="action" phx-click="known" phx-value-id={@selected.id}>{if @selected.status ==
                                                                                                   "known",
                                                                                                 do:
                                                                                                   "Keep learning",
                                                                                                 else:
                                                                                                   "I know this"}</button><button
            type="button"
            class="action action-danger"
            phx-click="delete"
            phx-value-id={@selected.id}
            data-confirm="Remove this word?"
          >Remove</button>
        </div>
      </StudyComponents.dialog>
    </Layouts.app>
    """
  end
end
