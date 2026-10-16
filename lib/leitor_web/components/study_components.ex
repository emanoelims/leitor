defmodule LeitorWeb.StudyComponents do
  @moduledoc false
  use LeitorWeb, :html

  @doc "Shares the visual frame of email sign-in and magic-link confirmation."
  slot :inner_block, required: true

  def auth_shell(assigns) do
    ~H"""
    <div id="auth-workspace" class="auth-layout">
      <div class="auth-introduction">
        <p class="auth-eyebrow">{gettext("A little space for a curious mind")}</p>
        <h1 class="auth-title">
          {gettext("Less noise.")}<br />{gettext("More")} <em>{gettext("meaning.")}</em>
        </h1>
        <p class="auth-description">
          {gettext("Bring a text. Follow a thought. Keep the words that stay with you.")}
        </p>
        <figure
          class="auth-reading-sample"
          aria-label={gettext("A preview of reading with margin notes")}
        >
          <div class="auth-sample-page">
            <p class="auth-sample-label">{gettext("A margin for your thoughts")} <span>01</span></p>
            <p class="auth-sample-text">
              {gettext("Read slowly. There is more here than")}
              <span>{gettext("a first glance")}</span> {gettext("can hold.")}
            </p>
            <div class="auth-sample-lines" aria-hidden="true"><span></span><span></span></div>
          </div>
          <figcaption class="auth-sample-note">
            <span class="auth-sample-connector" aria-hidden="true"></span>
            <span class="auth-sample-note-label">{gettext("A thought, kept.")}</span>
            {gettext("A second look is where understanding begins.")}
          </figcaption>
        </figure>
        <p class="auth-signature">{gettext("Read. Notice. Make it yours.")}</p>
      </div>
      <section class="auth-panel" aria-label={gettext("Your account")}>
        <div class="auth-panel-content stack">{render_slot(@inner_block)}</div>
        <p class="auth-panel-footnote">{gettext("Your pages. Your notes. A space of your own.")}</p>
      </section>
    </div>
    """
  end

  @doc "Renders the fixed reading and writing toolbar with caller-owned controls."
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :fixed, :boolean, default: true
  slot :inner_block, required: true

  def reading_toolbar(assigns) do
    ~H"""
    <nav
      id={@id}
      class={["reader-dock study-toolbar", @fixed && "study-toolbar-fixed"]}
      aria-label={t(@label)}
    >
      {render_slot(@inner_block)}
    </nav>
    """
  end

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
      <p class="eyebrow">{t(@label)}</p><p class="stat-value">{@value}</p><p
        :if={@detail}
        class="muted"
      >
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
    <progress class="study-progress" value={@value} max={max(@max, 1)} aria-label={t(@label)}>{@value} {gettext(
      "of"
    )} {@max}</progress>
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
              aria-label={gettext("Close dialog")}
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
