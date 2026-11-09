defmodule LeitorWeb.ReaderComponents do
  @moduledoc false
  use LeitorWeb, :html

  alias LeitorWeb.WritingComponents

  attr :face, :string, required: true
  attr :font_size, :integer, required: true
  attr :numbers, :boolean, default: nil
  attr :tab, :string, default: "look"
  attr :preferences, :map, default: %{}

  def appearance(assigns) do
    assigns =
      assigns
      |> assign(:size_form, to_form(%{"size" => assigns.font_size}))
      |> assign(:preferences, LeitorWeb.ReadingPreferences.normalize(assigns.preferences))

    ~H"""
    <.popover
      id="reading-appearance"
      class="reading-appearance"
      label={gettext("Reading appearance")}
      trigger_id="reading-font"
      trigger_class="layer-button reader-font"
      panel_class="reading-appearance-panel"
    >
      <:trigger><.icon name="lucide-thin-type" class="size-[18px]" /></:trigger>
      <span id="reading-appearance-controls" phx-hook="ReadingAppearance" phx-update="ignore" hidden></span>
      <div
        class="appearance-segments appearance-tabs"
        role="tablist"
        aria-label={gettext("Appearance section")}
      >
        <button
          :for={{key, label} <- [{"look", "Look"}, {"text", "Text"}]}
          id={"appearance-tab-#{key}"}
          type="button"
          role="tab"
          data-appearance-tab={key}
          aria-selected={to_string(@tab == key)}
          aria-controls={"appearance-panel-#{key}"}
          tabindex={if @tab == key, do: "0", else: "-1"}
          phx-click="appearance-tab"
          phx-value-tab={key}
        ><span>{t(label)}</span></button>
      </div>
      <div
        id="appearance-panel-look"
        role="tabpanel"
        aria-labelledby="appearance-tab-look"
        hidden={@tab != "look"}
        class="appearance-content"
      >
        <div>
          <p class="appearance-label">{gettext("Theme")}</p>
          <div class="appearance-themes">
            <button
              :for={
                {theme, label} <- [
                  {"auto", "Auto"},
                  {"light", "Paper"},
                  {"sepia", "Sepia"},
                  {"snow", "Snow"},
                  {"dark", "Night"},
                  {"ink", "Ink"}
                ]
              }
              id={"reading-theme-#{theme}"}
              type="button"
              class="appearance-theme"
              data-theme-choice={theme}
              aria-label={
                gettext("Use %{theme} theme",
                  theme: t(if theme == "dark", do: "Dark", else: String.capitalize(theme))
                )
              }
              aria-pressed="false"
              phx-click={JS.dispatch("leitor:set-theme", detail: %{theme: theme})}
            >
              <span class={"appearance-paper appearance-paper-#{theme}"} aria-hidden="true"><span :if={
                theme != "auto"
              }>{gettext("Aa")}</span><span :if={theme == "auto"} class="appearance-auto-light">{gettext(
                "A"
              )}</span><span
                :if={theme == "auto"}
                class="appearance-auto-dark"
              >{gettext("a")}</span></span>
              <span>{t(label)}</span>
            </button>
          </div>
        </div>
        <div class="appearance-row">
          <span>{gettext("Pen")}</span>
          <div class="appearance-pens">
            <button
              :for={
                {pen, label} <- [
                  {"vermilion", "Vermilion"},
                  {"cobalt", "Cobalt"},
                  {"moss", "Moss"},
                  {"graphite", "Graphite"}
                ]
              }
              id={"reading-pen-#{pen}"}
              type="button"
              class={"appearance-pen appearance-pen-#{pen}"}
              aria-label={gettext("%{color} pen", color: t(label))}
              aria-pressed={to_string(@preferences["pen"] == pen)}
              phx-click="reading-option"
              phx-value-key="pen"
              value={pen}
            ><span></span></button>
            <span class="appearance-pen-label">{t(String.capitalize(@preferences["pen"]))}</span>
          </div>
        </div>
        <div :if={!is_nil(@numbers)} class="reading-display-options">
          <button
            id="reading-paragraph-numbers"
            type="button"
            role="switch"
            aria-label={gettext("Paragraph numbers")}
            aria-checked={to_string(@numbers)}
            phx-click="reading-numbers"
          ><.icon name="lucide-pilcrow" class="size-3.5" /> {gettext("Numbers")}</button>
          <button
            :for={
              {key, label, icon} <- [
                {"rail", "Map", "lucide-map"},
                {"focus", "Focus", "lucide-focus"}
              ]
            }
            id={"reading-#{key}"}
            type="button"
            role="switch"
            aria-label={t(label)}
            aria-checked={to_string(@preferences[key])}
            phx-click="reading-option"
            phx-value-key={key}
            value={to_string(!@preferences[key])}
          ><.icon name={icon} class="size-3.5" /> {t(label)}</button>
        </div>
      </div>
      <div
        id="appearance-panel-text"
        role="tabpanel"
        aria-labelledby="appearance-tab-text"
        hidden={@tab != "text"}
        class="appearance-content"
      >
        <div>
          <p class="appearance-label">{gettext("Typeface")}</p>
          <div class="appearance-faces" role="group" aria-label={gettext("Reading font")}>
            <button
              :for={
                {face, label} <- [
                  {"serif", "Serif"},
                  {"book", "Book"},
                  {"sans", "Sans"},
                  {"legible", "Legible"}
                ]
              }
              id={"font-#{face}"}
              type="button"
              class={"appearance-face appearance-face-#{face}"}
              aria-label={
                %{
                  "serif" => "Newsreader",
                  "book" => "Literata",
                  "sans" => "Schibsted",
                  "legible" => "Atkinson Hyperlegible Next"
                }[face]
              }
              aria-pressed={to_string(@face == face)}
              phx-click="reading-face"
              phx-value-face={face}
            ><span aria-hidden="true">{gettext("Ag")}</span><small>{t(label)}</small></button>
          </div>
        </div>
        <.form
          for={@size_form}
          id="reading-size-form"
          phx-change="reading-size"
          class="appearance-row"
        >
          <label for="reading-text-size">{gettext("Size")}</label>
          <div class="appearance-size">
            <button
              id="reading-size-smaller"
              type="button"
              aria-label={gettext("Smaller text")}
              phx-click="reading-size"
              phx-value-size={max(15, @font_size - 1)}
              disabled={@font_size == 15}
            ><.icon name="lucide-minus" class="size-3.5" /></button>
            <.input
              field={@size_form[:size]}
              type="range"
              id="reading-text-size"
              min="15"
              max="28"
              step="1"
              aria-label={gettext("Text size")}
              class="appearance-size-range"
            />
            <button
              id="reading-size-larger"
              type="button"
              aria-label={gettext("Larger text")}
              phx-click="reading-size"
              phx-value-size={min(28, @font_size + 1)}
              disabled={@font_size == 28}
            ><.icon name="lucide-plus" class="size-3.5" /></button>
            <output id="reading-size-value" for="reading-text-size">{@font_size}</output>
          </div>
        </.form>
        <div
          :for={
            {key, label, group, options} <- [
              {"leading", "Spacing", "Line spacing",
               [{"tight", "Snug"}, {"normal", "Even"}, {"loose", "Airy"}]},
              {"width", "Width", "Column width",
               [{"narrow", "Narrow"}, {"normal", "Even"}, {"wide", "Wide"}]},
              {"align", "Align", "Text alignment", [{"left", "Left"}, {"justify", "Justified"}]},
              {"paras", "Paragraphs", "Paragraph style",
               [{"spaced", "Spaced"}, {"indented", "Indented"}]}
            ]
          }
          class="appearance-row"
        >
          <span>{t(label)}</span>
          <div
            class={["appearance-segments", "appearance-segments-#{length(options)}"]}
            role="radiogroup"
            aria-label={t(group)}
          >
            <button
              :for={{value, option_label} <- options}
              id={"reading-#{key}-#{value}"}
              type="button"
              role="radio"
              aria-checked={to_string(@preferences[key] == value)}
              phx-click="reading-option"
              phx-value-key={key}
              value={value}
            ><span><.icon
              :if={key == "align"}
              name={if value == "left", do: "lucide-align-left", else: "lucide-align-justify"}
              class="size-3"
            /> {t(option_label)}</span></button>
          </div>
        </div>
        <button
          :if={
            @face != "serif" || @font_size != 20 ||
              Enum.any?(
                ~w(leading width align paras),
                &(@preferences[&1] != LeitorWeb.ReadingPreferences.defaults()[&1])
              )
          }
          id="reading-text-reset"
          type="button"
          class="appearance-reset"
          phx-click="reading-text-reset"
        ><.icon name="lucide-rotate-ccw" class="size-3" /> {gettext("Reset text settings")}</button>
      </div>
    </.popover>
    """
  end

  attr :id, :string, required: true
  attr :kind, :string, default: nil
  attr :active, :boolean, default: true
  attr :entering, :boolean, default: false
  attr :layout, :string, default: "margin", values: ["margin", "stack"]
  attr :rest, :global
  slot :inner_block, required: true

  def annotation_frame(assigns) do
    ~H"""
    <article
      id={@id}
      data-card-layout={@layout}
      class={[
        "page-margin-card",
        @kind && "mark-#{@kind}",
        if(@active, do: "is-active", else: "is-collapsed"),
        @entering && "is-entering"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </article>
    """
  end

  attr :id, :string, required: true
  attr :mark, :map, required: true
  attr :document, :map, required: true
  attr :active, :boolean, default: false
  attr :layout, :string, default: "margin", values: ["margin", "stack"]
  attr :busy, :boolean, default: false
  attr :pending, :map, default: nil
  attr :help_stream, :map, default: nil
  attr :actions, :list, default: [:retry, :edit, :follow, :collect]

  def annotation(assigns) do
    ~H"""
    <.annotation_frame
      id={@id}
      kind={@mark.kind}
      layout={@layout}
      active={@active}
      data-margin-mark={@mark.id}
      data-margin-kind={@mark.kind}
    >
      <button
        :if={!@active}
        type="button"
        class="page-card-summary"
        phx-click="activate-mark"
        phx-value-id={@mark.id}
      >
        <span><strong>{t(annotation_title(@mark))}</strong> “{@mark.quote}”</span><span class="page-cite">¶{@mark.block_index +
          1}</span>
        <small>{answer_summary(@mark.body)}</small>
      </button>
      <div :if={@active} class="page-card-expanded">
        <header>
          <strong>{t(annotation_title(@mark))}</strong><button
            type="button"
            class="page-cite"
            data-page-cite-mark={@mark.id}
            aria-label={gettext("Go to paragraph %{number}", number: @mark.block_index + 1)}
            phx-click="jump-mark"
            phx-value-id={@mark.id}
          >¶{@mark.block_index + 1}</button><span
            :if={@mark.replies != []}
            class="page-follow-count"
          >{ngettext("%{count} follow-up", "%{count} follow-ups", length(@mark.replies))}</span><button
            type="button"
            class="icon-button"
            phx-click="collapse-mark"
            aria-label={gettext("Collapse note")}
          ><.icon name="lucide-chevrons-down-up" class="size-3" /></button>
        </header>
        <blockquote>{@mark.quote}</blockquote>
        <h3 :if={@mark.kind == "answer" && annotation_title(@mark) == "Ask"}>{@mark.question}</h3>
        <div class="page-answer">
          {answer_html(
            if(
              @busy && @pending && @pending.mark_id == @mark.id && @pending.action == "retry" &&
                @help_stream && @help_stream.answer != "",
              do: @help_stream.answer,
              else: @mark.body
            ),
            @document
          )}
        </div>
        <div
          :for={reply <- @mark.replies}
          id={"#{@id}-reply-#{reply.id}"}
          class="page-follow-turn"
        >
          <h4><.icon name="lucide-corner-down-right" class="size-3" />{reply.question}</h4><div class="page-answer">
            {answer_html(reply.body, @document)}
          </div>
        </div>
        <div
          :if={
            @busy && @pending && @pending.mark_id == @mark.id && @pending.action == "follow" &&
              @help_stream && @help_stream.answer != ""
          }
          class="page-follow-turn page-follow-pending"
          aria-busy="true"
        >
          <h4>
            <.icon name="lucide-corner-down-right" class="size-3" />{@pending.question}
          </h4>
          <div class="page-answer">{answer_html(@help_stream.answer, @document)}</div>
        </div>
        <WritingComponents.generating :if={
          @busy && @pending && @pending.mark_id == @mark.id &&
            (!@help_stream || @help_stream.answer == "")
        } />
        <footer>
          <span>{if @mark.kind in ["note", "highlight"],
            do: gettext("Your note"),
            else: gettext("Claude")}</span>
          <button
            :if={@busy && @pending && @pending.mark_id == @mark.id}
            type="button"
            class="icon-button"
            phx-click="stop-help"
            aria-label={gettext("Stop response")}
          ><.icon name="lucide-square" class="size-3" /></button>
          <button
            :if={:retry in @actions && @mark.kind in ["definition", "answer"]}
            type="button"
            class="icon-button"
            phx-click="retry-mark"
            phx-value-id={@mark.id}
            disabled={@busy}
            aria-label={gettext("Try again")}
          ><.icon name="lucide-rotate-ccw" class="size-4" /></button>
          <button
            type="button"
            class="icon-button"
            phx-click={
              JS.dispatch("leitor:copy",
                detail: %{text: annotation_markdown(@mark), status_id: "mark-copy-#{@mark.id}"}
              )
            }
            aria-label={gettext("Copy annotation")}
          ><.icon name="lucide-copy" class="size-4" /></button>
          <button
            :if={:edit in @actions && @mark.kind == "note"}
            type="button"
            class="icon-button"
            phx-click="edit-note"
            phx-value-id={@mark.id}
            aria-label={gettext("Edit note")}
          ><.icon name="lucide-pen-line" class="size-4" /></button>
          <button
            type="button"
            class="icon-button"
            phx-click="remove-mark"
            phx-value-id={@mark.id}
            aria-label={gettext("Remove annotation")}
          ><.icon name="lucide-trash-2" class="size-4" /></button>
        </footer>
        <p
          id={"mark-copy-#{@mark.id}"}
          phx-update="ignore"
          class="page-copy-status"
          role="status"
        >
        </p>
        <.form
          :if={:follow in @actions && @mark.kind in ["definition", "answer"]}
          for={to_form(%{"question" => ""}, as: "follow")}
          id={"follow-up-#{@mark.id}"}
          phx-submit="follow-up"
          phx-value-id={@mark.id}
          class="page-follow-form"
        >
          <.input
            name="follow[question]"
            value=""
            id={"follow-question-#{@mark.id}"}
            aria-label={gettext("Ask a follow-up")}
            placeholder={gettext("Ask a follow-up…")}
            maxlength="500"
            required
            class="page-follow-input"
            disabled={@busy}
          /><button type="submit" aria-label={gettext("Send follow-up")} disabled={@busy}><.icon
            name="lucide-arrow-up"
            class="size-4"
          /></button>
        </.form>
        <button
          :if={:collect in @actions && String.length(@mark.quote) <= 200}
          type="button"
          class="page-collect-word"
          phx-click="mark-to-pot"
          phx-value-id={@mark.id}
        ><.icon name="hero-beaker" class="size-3" />{gettext("Keep in a jar")}</button>
      </div>
    </.annotation_frame>
    """
  end

  attr :id, :string, required: true
  attr :pending, :map, required: true
  attr :document, :map, required: true
  attr :answer, :string, default: ""
  attr :layout, :string, default: "margin", values: ["margin", "stack"]

  def pending_annotation(assigns) do
    ~H"""
    <.annotation_frame
      id={@id}
      layout={@layout}
      entering
      data-margin-mark="pending"
      data-margin-block={@pending.block_index}
      aria-busy="true"
    >
      <header>
        <strong>{t(String.capitalize(@pending.action))}</strong><span class="page-cite">¶{@pending.block_index +
          1}</span><button
          type="button"
          class="icon-button"
          phx-click="stop-help"
          aria-label={gettext("Stop response")}
        ><.icon name="lucide-square" class="size-3" /></button>
      </header>
      <blockquote>{@pending.quote}</blockquote>
      <div
        :if={@answer != ""}
        class="page-answer page-stream-answer"
      >
        {answer_html(@answer, @document)}
      </div>
      <WritingComponents.generating :if={@answer == ""} />
      <footer><span>{gettext("Reading your passage…")}</span></footer>
    </.annotation_frame>
    """
  end

  def citation_preview(assigns) do
    ~H"""
    <div
      id="page-citation-preview"
      phx-hook="PageCitations"
      phx-update="ignore"
      class="page-cite-preview"
      role="tooltip"
      hidden
    >
      <p data-cite-number></p><p data-cite-text></p><p>{gettext("Click to jump there")}</p>
    </div>
    """
  end

  defp annotation_title(%{kind: "highlight"}), do: gettext_noop("Highlight")
  defp annotation_title(%{kind: "note"}), do: "Note"
  defp annotation_title(%{kind: "definition", question: "Dictionary"}), do: "Dictionary"
  defp annotation_title(%{kind: "definition"}), do: "Define"
  defp annotation_title(%{question: question}) when question in ["Explain", "Simplify"], do: question
  defp annotation_title(_), do: "Ask"

  defp answer_html(markdown, document),
    do: Phoenix.HTML.raw(Leitor.PageDocument.render_answer(markdown, length(document.blocks)))

  defp answer_summary(markdown), do: Leitor.PageDocument.prepare(markdown).text

  defp annotation_markdown(mark),
    do:
      "> #{String.replace(mark.quote, "\n", "\n> ")}\n\n#{mark.body}" <>
        Enum.map_join(mark.replies, "", &"\n\n### #{&1.question}\n\n#{&1.body}")
end
