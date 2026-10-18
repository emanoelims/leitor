defmodule LeitorWeb.WritingComponents do
  @moduledoc false
  use LeitorWeb, :html

  attr :text, :string, required: true
  attr :format, :string, default: "markdown"

  def prose(assigns) do
    ~H"""
    <%= if @format == "markdown" do %>
      {Phoenix.HTML.raw(Leitor.WritingDocument.render(@text))}
    <% else %>
      <p :for={paragraph <- Leitor.WritingDocument.paragraphs(@text, "plain")}>{paragraph.text}</p>
    <% end %>
    """
  end

  def slash_menu(assigns) do
    assigns =
      assign(assigns, :commands, [
        {"paragraph", "Text", "Plain paragraph", "hero-bars-3"},
        {"h1", "Heading 1", "#", "hero-h1"},
        {"h2", "Heading 2", "##", "hero-h2"},
        {"h3", "Heading 3", "###", "hero-h3"},
        {"bullet", "Bullet list", "-", "hero-list-bullet"},
        {"ordered", "Numbered list", "1.", "hero-numbered-list"},
        {"task", "Checklist", "[ ]", "hero-check-circle"},
        {"quote", "Quote", ">", "hero-chat-bubble-left"},
        {"code", "Code block", "```", "hero-code-bracket"},
        {"divider", "Divider", "---", "hero-minus"},
        {"figure", "Example figure", "", "lucide-box"},
        {"ai", "Generate with AI", "", "lucide-feather"}
      ])

    ~H"""
    <div id="writing-block-menu" class="writing-block-menu" hidden>
      <div id="writing-block-options" role="listbox" aria-label={gettext("Block types")}>
        <button
          :for={{command, label, shortcut, icon} <- @commands}
          id={"writing-block-#{command}"}
          type="button"
          role="option"
          aria-selected="false"
          tabindex="-1"
          data-command={command}
          data-search={String.downcase(label <> " " <> t(label))}
        >
          <.icon name={icon} class="size-4" />
          <span>{t(label)}</span><small>{t(shortcut)}</small>
        </button>
        <p id="writing-block-empty" class="muted" hidden>{gettext("No matching blocks")}</p>
      </div>
      <footer class="writing-block-help">
        {gettext("↑↓ to choose · Enter to insert · Esc to close")}
      </footer>
    </div>
    """
  end

  def ai_composer(assigns) do
    ~H"""
    <section
      id="page-ai-composer"
      class="page-ai-composer"
      role="dialog"
      aria-label={gettext("Generate with AI")}
      hidden
    >
      <header>
        <span><.icon name="lucide-feather" class="size-4" /><span data-ai-title>{gettext(
          "Generate with AI"
        )}</span></span>
        <button
          id="page-ai-close"
          type="button"
          class="icon-button"
          aria-label={gettext("Close AI prompt")}
        >
          <.icon name="lucide-x" class="size-4" />
        </button>
      </header>
      <div class="page-ai-format">
        <.input
          id="page-ai-format"
          name="ai_format"
          type="select"
          value="visual_explainer"
          label={gettext("Writing format")}
          options={
            Enum.map(Leitor.WritingFormat.options(), fn {label, id} -> {t(label), id} end) ++
              Enum.map(Leitor.WritingFormat.planned(), fn {label, id} ->
                [key: t(label) <> " · " <> gettext("Coming soon"), value: id, disabled: true]
              end)
          }
        />
      </div>
      <p class="figure-coming-soon">
        {gettext("Coming soon: stories, poems, manga and other creative formats.")}
      </p>
      <div id="page-ai-input">
        <.input
          id="page-ai-prompt"
          name="ai_prompt"
          value=""
          type="textarea"
          aria-label={gettext("What would you like to write?")}
          placeholder={gettext("Describe what you’d like to write…")}
          maxlength="2000"
          rows="3"
        />
      </div>
      <p id="page-ai-error" class="page-ai-error" role="alert" hidden></p>
      <template id="page-ai-waiting"><.generating /></template>
      <footer>
        <small id="page-ai-hint">{gettext("Enter to generate · Shift Enter for a new line")}</small>
        <button id="page-ai-generate" type="button"><span>{gettext("Generate")}</span><.icon
          name="lucide-arrow-up"
          class="size-4"
        /></button>
      </footer>
    </section>
    """
  end

  def generating(assigns) do
    ~H"""
    <div class="page-writing" role="status" aria-label={gettext("Writing")}>
      <span aria-hidden="true"></span><span aria-hidden="true"></span><span aria-hidden="true"></span>
    </div>
    """
  end
end
