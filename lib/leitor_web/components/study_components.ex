defmodule LeitorWeb.StudyComponents do
  @moduledoc false
  use LeitorWeb, :html

  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_heading(assigns) do
    ~H"""
    <div class="page-heading">
      <div>
        <p :if={@eyebrow} class="eyebrow">{@eyebrow}</p><h1>{@title}</h1><p
          :if={@subtitle}
          class="muted heading-subtitle"
        >
          {@subtitle}
        </p>
      </div>
      <div :if={@actions != []} class="heading-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :icon, :string, default: "hero-book-open"
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="empty-state">
      <span class="empty-icon"><.icon name={@icon} class="size-7" /></span>
      <h2>{@title}</h2><p class="muted">{@body}</p><div>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :detail, :string, default: nil
  attr :class, :string, default: ""

  def stat(assigns) do
    ~H"""
    <section class={["stat-card", @class]}>
      <p class="eyebrow">{@label}</p><p class="stat-value">{@value}</p><p :if={@detail} class="muted">
        {@detail}
      </p>
    </section>
    """
  end

  attr :category, :string, default: "word"
  attr :rest, :global
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <span class={["word-chip", "pos-#{@category}"]} {@rest}>{render_slot(@inner_block)}</span>
    """
  end

  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :label, :string, required: true

  def progress(assigns) do
    ~H"""
    <progress class="study-progress" value={@value} max={max(@max, 1)} aria-label={@label}>{@value} of {@max}</progress>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :on_close, :any, required: true
  slot :inner_block, required: true

  def dialog(assigns) do
    ~H"""
    <div
      id={@id}
      class="dialog-backdrop"
      phx-remove={JS.pop_focus()}
      phx-window-keydown={@on_close}
      phx-key="Escape"
    >
      <.focus_wrap id={@id <> "-focus"}>
        <section
          role="dialog"
          aria-modal="true"
          aria-labelledby={@id <> "-title"}
          class="dialog-card"
          phx-click-away={@on_close}
          phx-mounted={JS.focus_first()}
        >
          <header class="dialog-header">
            <h2 id={@id <> "-title"}>{@title}</h2><button
              type="button"
              class="icon-button"
              aria-label="Close dialog"
              phx-click={@on_close}
            ><.icon name="hero-x-mark" class="size-5" /></button>
          </header>
          {render_slot(@inner_block)}
        </section>
      </.focus_wrap>
    </div>
    """
  end
end
