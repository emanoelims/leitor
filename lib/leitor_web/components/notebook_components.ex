defmodule LeitorWeb.NotebookComponents do
  @moduledoc "Function components for the combined notebook's collected words."
  use LeitorWeb, :html

  attr :word_filter, :string, required: true
  attr :word_search_form, :any, required: true
  attr :hide_empty, :boolean, required: true

  def word_filters(assigns) do
    ~H"""
    <p class="workspace-submenu-heading">{gettext("Find a collected word")}</p>
    <.form
      for={@word_search_form}
      id="word-search"
      phx-change="word-search"
      class="workspace-filter-form"
    >
      <.input
        field={@word_search_form[:search]}
        type="search"
        label={gettext("Find a collected word")}
        placeholder={gettext("A word, a meaning, a memory…")}
        phx-debounce="250"
        maxlength="200"
      />
      <button
        id="hide-empty-jars"
        type="button"
        class="workspace-quiet-action"
        phx-click="hide-empty"
        aria-pressed={to_string(@hide_empty)}
      >
        <.icon name="lucide-thin-flask-conical" class="size-4" /> {gettext("Only filled jars")}
      </button>
    </.form>
    <div class="workspace-filter-choices" role="group" aria-label={gettext("Vocabulary filters")}>
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
        class={[@word_filter == value && "active"]}
        aria-pressed={@word_filter == value}
        phx-click="word-category"
        phx-value-category={value}
      >{t(label)}</button>
    </div>
    """
  end

  attr :streams, :map, required: true
  attr :word_search, :string, required: true
  attr :word_form, :any, required: true
  attr :hide_empty, :boolean, required: true
  attr :count, :integer, required: true
  attr :selected, :any, required: true

  def word_jars(assigns) do
    ~H"""
    <div class="word-results-heading">
      <p class="eyebrow !mb-0">
        {ngettext("%{count} collected word", "%{count} collected words", @count)}
      </p><.link
        navigate={~p"/pages"}
        class="text-link text-sm"
      >{gettext("Find something new →")}</.link>
    </div>
    <div
      :if={@count == 0 && (@hide_empty || @word_search != "")}
      id="words-empty"
      class="workspace-empty"
    >
      <.icon name="lucide-thin-flask-conical" class="size-8" />
      <h2>
        {if @word_search == "",
          do: gettext("A place for every new word."),
          else: gettext("No words found.")}
      </h2>
      <p>{gettext("Collect a word as you read. Its meaning and context will be waiting here.")}</p>
      <.link navigate={~p"/pages"} class="text-link">{gettext("Find a page to read")}
      <.icon name="lucide-thin-arrow-right" class="size-4" /></.link>
    </div>
    <p :if={@count == 200} class="muted text-xs mb-4">
      {gettext("Showing your latest 200 matches. Search to find older words.")}
    </p>
    <div id="vocabulary-entries" phx-update="stream" class="jar-grid">
      <section
        :for={{id, jar} <- @streams.jars}
        id={id}
        class="jar-card"
        data-empty={to_string(jar.count == 0)}
        aria-label={t(jar.label)}
      >
        <div class="row between">
          <div class="row">
            <span class="jar-icon" aria-hidden="true"><i class={"pos-#{jar.category}"}></i></span><div>
              <h2>{t(jar.label)}</h2><p class="muted text-[13px]">{t(jar.hint)}</p>
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
            aria-label={gettext("Known")}
          >✓</span></button>
        </div>
        <p :if={jar.words == []} class="muted text-sm mt-auto">{gettext("Empty for now.")}</p>
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
        for={@word_form}
        id="entry-edit"
        phx-submit="edit"
      >
        <.input
          field={@word_form[:meaning]}
          label={gettext("Meaning / learning note")}
          required
          maxlength="2000"
        />
        <.input
          field={@word_form[:category]}
          type="select"
          label={gettext("Jar")}
          options={
            LeitorWeb.I18n.options(
              ~w(word noun verb aux adj adv pron prep det conj proper expression error)
            )
          }
        />
        <.button variant="primary">{gettext("Save changes")}</.button>
      </.form>
      <div class="row mt-5">
        <button type="button" class="action" phx-click="known" phx-value-id={@selected.id}>{if @selected.status ==
                                                                                                 "known",
                                                                                               do:
                                                                                                 gettext(
                                                                                                   "Keep learning"
                                                                                                 ),
                                                                                               else:
                                                                                                 gettext(
                                                                                                   "I know this"
                                                                                                 )}</button><button
          type="button"
          class="action action-danger"
          phx-click="delete"
          phx-value-id={@selected.id}
          data-confirm={gettext("Remove this word?")}
        >{gettext("Remove")}</button>
      </div>
    </StudyComponents.dialog>
    """
  end
end
