defmodule LeitorWeb.WritingComponents do
  @moduledoc false
  use LeitorWeb, :html

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
        {"divider", "Divider", "---", "hero-minus"}
      ])

    ~H"""
    <div id="writing-block-menu" class="writing-block-menu" hidden>
      <p class="eyebrow">Add a block</p>
      <div id="writing-block-options" role="listbox" aria-label="Block types">
        <button
          :for={{command, label, shortcut, icon} <- @commands}
          id={"writing-block-#{command}"}
          type="button"
          role="option"
          aria-selected="false"
          tabindex="-1"
          data-command={command}
          data-search={String.downcase(label)}
        >
          <.icon name={icon} class="size-4" />
          <span>{label}</span><small>{shortcut}</small>
        </button>
      </div>
      <p id="writing-block-empty" class="muted" hidden>No matching blocks</p>
      <p class="writing-block-help">↑↓ to choose · Enter to insert · Esc to close</p>
    </div>
    """
  end
end
