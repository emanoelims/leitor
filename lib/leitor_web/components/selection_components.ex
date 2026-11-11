defmodule LeitorWeb.SelectionComponents do
  @moduledoc false
  use LeitorWeb, :html

  attr :selection, :any, required: true
  attr :editing, :boolean, required: true
  attr :selection_mode, :any, required: true
  attr :selection_anchor, :any, required: true
  attr :page_title, :any, required: true
  attr :busy, :boolean, required: true
  attr :marker_color, :any, required: true
  attr :editing_highlight_id, :any, required: true
  attr :editing_highlight_color, :any, required: true
  attr :note_form, :any, required: true
  attr :question_form, :any, required: true
  attr :pot_form, :any, required: true
  attr :error, :any, required: true
  attr :shared, :boolean, default: false

  def selection(assigns) do
    ~H"""
    <section
      :if={@selection && !@editing}
      id="page-selection"
      class={[
        "page-selection",
        @selection_mode == "actions" && "page-selection-actions",
        @selection_mode != "actions" && "page-selection-expanded"
      ]}
      role={if @selection_mode == "actions", do: "toolbar", else: "dialog"}
      aria-label={gettext("Actions for the selection")}
      data-selection-version={@selection_anchor["selection_version"]}
      phx-window-keydown="close-selection"
      phx-key="Escape"
    >
      <%= case @selection_mode do %>
        <% "actions" -> %>
          <div class="selection-tools">
            <button id="selection-ask" type="button" phx-click="selection-mode" phx-value-mode="ask">{gettext(
              "Ask"
            )}
            <span class="selection-caret" aria-hidden="true"></span></button>
            <button
              :if={@shared}
              id="selection-comment"
              type="button"
              phx-click="selection-mode"
              phx-value-mode="comment"
            ><.icon name="lucide-notebook-pen" class="size-[15px]" /><span>{gettext("Comment")}</span></button>
            <span class="selection-divider"></span>
            <button
              id="selection-explain"
              type="button"
              phx-click="help"
              phx-value-action="explain"
              disabled={@busy}
            ><.icon name="lucide-lightbulb" class="size-[15px]" /><span>{gettext("Explain")}</span></button>
            <button
              id={
                if length(String.split(@selection.quote)) <= 4,
                  do: "selection-define",
                  else: "selection-simplify"
              }
              type="button"
              phx-click="help"
              phx-value-action={
                if length(String.split(@selection.quote)) <= 4, do: "define", else: "simplify"
              }
              disabled={@busy}
            ><.icon
              name={
                if length(String.split(@selection.quote)) <= 4,
                  do: "lucide-book-a",
                  else: "lucide-feather"
              }
              class="size-[15px]"
            /><span>{if length(String.split(@selection.quote)) <= 4,
              do: gettext("Define"),
              else: gettext("Simplify")}</span></button>
            <button
              :if={String.length(@selection.quote) <= 200}
              id="selection-dictionary"
              type="button"
              phx-click="help"
              phx-value-action="dictionary"
              disabled={@busy}
            ><.icon name="lucide-languages" class="size-[15px]" /><span>{gettext("Dictionary")}</span></button>
            <details id="selection-more" class="selection-more">
              <summary aria-label={gettext("More actions")} title={gettext("More actions")}>
                <.icon name="lucide-ellipsis" class="size-4" />
              </summary><div class="selection-more-menu">
                <button
                  id={
                    if length(String.split(@selection.quote)) <= 4,
                      do: "selection-simplify",
                      else: "selection-define"
                  }
                  type="button"
                  phx-click="help"
                  phx-value-action={
                    if length(String.split(@selection.quote)) <= 4, do: "simplify", else: "define"
                  }
                  disabled={@busy}
                ><.icon
                  name={
                    if length(String.split(@selection.quote)) <= 4,
                      do: "lucide-feather",
                      else: "lucide-book-a"
                  }
                  class="size-4"
                />{if length(String.split(@selection.quote)) <= 4,
                  do: gettext("Simplify"),
                  else: gettext("Define")}</button><button
                  type="button"
                  phx-click={
                    JS.dispatch("leitor:copy",
                      detail: %{
                        text:
                          "> #{@selection.quote}\n\n— #{@page_title}, ¶#{@selection.block_index + 1}",
                        status_id: "selection-copy-status"
                      }
                    )
                  }
                ><.icon name="lucide-copy" class="size-4" />{gettext("Copy quote")}</button>
                <button
                  :if={String.length(@selection.quote) <= 200}
                  id="selection-pot"
                  type="button"
                  aria-label={gettext("Keep in a jar")}
                  title={gettext("Keep in a jar")}
                  phx-click="selection-mode"
                  phx-value-mode="pot"
                ><.icon name="lucide-flask-conical" class="size-4" />{gettext("Keep in a jar")}</button>
              </div>
            </details>
            <span class="selection-divider"></span>
            <div class={["selection-highlighter", @editing_highlight_id && "is-editing"]}>
              <button
                :if={!@editing_highlight_id}
                id="selection-highlight"
                type="button"
                aria-label={gettext("Highlight text")}
                title={gettext("Highlight text")}
                phx-click="highlight"
                phx-value-color={@marker_color}
              ><.icon name="lucide-highlighter" class="size-[15px]" /><span
                class="selection-color-dot selection-marker-color"
                data-color={@marker_color}
                aria-hidden="true"
              ></span></button>
              <div class="selection-colors-reveal">
                <div
                  id="selection-highlight-palette"
                  class="selection-colors"
                  role="group"
                  aria-label={gettext("Highlight color")}
                >
                  <button
                    :for={
                      {color, label} <- [
                        {"yellow", gettext("Yellow")},
                        {"green", gettext("Green")},
                        {"blue", gettext("Blue")},
                        {"rose", gettext("Rose")}
                      ]
                    }
                    id={"selection-highlight-#{color}"}
                    type="button"
                    class="selection-marker-color"
                    data-color={color}
                    aria-label={gettext("Highlight in %{color}", color: label)}
                    aria-pressed={to_string((@editing_highlight_color || @marker_color) == color)}
                    phx-click="highlight"
                    phx-value-color={color}
                  ></button>
                </div>
              </div>
            </div>
            <button
              id="selection-note"
              type="button"
              aria-label={gettext("Add a note")}
              title={gettext("Add a note")}
              phx-click="selection-mode"
              phx-value-mode="note"
            ><.icon name="lucide-pen-line" class="size-[15px]" /></button>
            <button
              :if={@editing_highlight_id}
              id="selection-highlight-remove"
              type="button"
              aria-label={gettext("Remove highlight")}
              title={gettext("Remove highlight")}
              phx-click="remove-mark"
              phx-value-id={@editing_highlight_id}
            ><.icon name="lucide-eraser" class="size-[15px]" /></button>
          </div>
          <p id="selection-copy-status" phx-update="ignore" class="sr-only" role="status"></p>
        <% "note" -> %>
          <.form for={@note_form} id="selection-note-form" phx-submit="note">
            <.input
              field={@note_form[:body]}
              id="selected-note-body"
              type="textarea"
              label={gettext("Your note on the selection")}
              placeholder={gettext("A thought, in your own words")}
              maxlength="4000"
              required
              phx-mounted={JS.focus()}
            /><button type="submit">{gettext("Keep note")}
            <.icon name="lucide-check" class="size-4" /></button>
          </.form>
        <% "ask" -> %>
          <.form for={@question_form} id="selection-question-form" phx-submit="help">
            <input type="hidden" name="action" value="ask" /><.input
              field={@question_form[:question]}
              id="selection-question-input"
              label={gettext("Question about the selection")}
              placeholder={gettext("Ask about this passage…")}
              maxlength="500"
              required
              phx-mounted={JS.focus()}
            /><button type="submit" disabled={@busy}>{gettext("Ask")}
            <.icon name="lucide-arrow-up" class="size-4" /></button>
          </.form>
        <% "pot" -> %>
          <.form for={@pot_form} id="selection-pot-form" phx-submit="save-pot">
            <p class="selection-quote">{@selection.quote}</p><.input
              field={@pot_form[:meaning]}
              label={gettext("Meaning")}
              placeholder={gettext("What does this word mean?")}
              maxlength="2000"
              required
              phx-mounted={JS.focus()}
            /><.input
              field={@pot_form[:category]}
              type="select"
              label={gettext("Word jar")}
              options={
                LeitorWeb.I18n.options([
                  {"Other words", "word"},
                  {"Nouns", "noun"},
                  {"Verbs", "verb"},
                  {"Adjectives", "adj"},
                  {"Adverbs", "adv"},
                  {"Pronouns", "pron"},
                  {"Prepositions", "prep"},
                  {"Expressions", "expression"}
                ])
              }
            /><button type="submit">{gettext("Save word")}
            <.icon name="hero-beaker" class="size-4" /></button>
          </.form>
      <% end %>
      <p :if={@error} class="notice" role="alert">{t(@error)}</p>
      <span id="page-selection-positioner" phx-hook="PagePopup" phx-update="ignore" hidden></span>
    </section>
    """
  end
end
