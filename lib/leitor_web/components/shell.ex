defmodule LeitorWeb.Shell do
  @moduledoc false
  use LeitorWeb, :html

  attr :current_scope, :any, default: nil
  attr :active, :string, default: "read"
  attr :context_title, :string, default: nil
  attr :context_detail, :string, default: nil
  attr :speech, :string, default: nil
  slot :controls

  def header(assigns) do
    assigns =
      assign(
        assigns,
        :section_title,
        assigns.context_title ||
          %{
            "library" => "Your texts",
            "vocabulary" => "Word jars",
            "review" => "Review",
            "write" => "Writing",
            "lessons" => "Lesson materials",
            "progress" => "Progress",
            "rooms" => "Study together",
            "practice" => "Practice"
          }[assigns.active]
      )

    ~H"""
    <a href="#main-content" class="skip-link">Skip to content</a>
    <header id="app-header" class="app-header">
      <div class="header-inner">
        <div class="header-left">
          <%= if @section_title do %>
            <.link navigate={~p"/"} class="icon-button home-button" aria-label="Back to home"><.icon
              name="hero-home"
              class="size-5"
            /></.link>
            <span class="header-divider" aria-hidden="true"></span>
            <button
              :if={@speech}
              id="header-listen"
              class="icon-button"
              aria-label="Listen to the sentence"
              phx-click={JS.dispatch("leitor:speak", detail: %{text: @speech})}
            ><.icon name="hero-speaker-wave" class="size-4" /></button>
            <span class="context-title">{@section_title}</span><span
              :if={@context_detail}
              class="context-detail"
            >{@context_detail}</span>
          <% else %>
            <.link navigate={~p"/"} class="brand" aria-label="Leitor home"><.icon
              name="hero-book-open"
              class="size-5"
            /> Leitor</.link>
            <span class="header-divider" aria-hidden="true"></span>
            <nav id="primary-nav" aria-label="Main navigation" class="primary-nav">
              <.nav_item navigate={~p"/"} icon="hero-home" label="Home" active={@active == "read"} />
              <.nav_item
                navigate={~p"/library"}
                icon="hero-book-open"
                label="Read"
                active={@active == "library"}
              />
              <.nav_item
                navigate={~p"/vocabulary"}
                icon="hero-beaker"
                label="Word jars"
                active={@active == "vocabulary"}
              />
              <.nav_item
                navigate={~p"/write"}
                icon="hero-pencil-square"
                label="Write"
                active={@active == "write"}
              />
              <.nav_item
                navigate={~p"/review"}
                icon="hero-arrow-path"
                label="Review"
                active={@active == "review"}
              />
              <.nav_item
                navigate={~p"/lessons"}
                icon="hero-academic-cap"
                label="Lessons"
                active={@active == "lessons"}
              />
              <.nav_item
                navigate={~p"/progress"}
                icon="hero-chart-bar"
                label="Progress"
                active={@active == "progress"}
              />
              <.nav_item
                navigate={~p"/rooms"}
                icon="hero-user-group"
                label="Study together"
                active={@active == "rooms"}
              />
            </nav>
          <% end %>
        </div>
        <div class="header-actions">
          {render_slot(@controls)}
          <span :if={@controls != []} class="header-divider" aria-hidden="true"></span>
          <button
            id="theme-toggle"
            type="button"
            class="icon-button theme-toggle"
            aria-label="Toggle dark theme"
            phx-click={JS.dispatch("leitor:theme")}
          ><.icon name="hero-moon" class="size-4" /></button>
          <%= if @current_scope do %>
            <details
              id="account-menu"
              class="account-menu"
              phx-window-keydown={
                JS.focus(to: "#account-menu[open] > summary")
                |> JS.remove_attribute("open", to: "#account-menu")
              }
              phx-key="Escape"
            >
              <summary
                id="account-menu-trigger"
                class="avatar"
                title={@current_scope.user.email}
                aria-label="Account menu"
              >
                {String.upcase(String.first(@current_scope.user.email))}
              </summary>
              <nav
                class="account-popover stack"
                aria-label="Account"
                phx-click-away={JS.remove_attribute("open", to: "#account-menu")}
              >
                <.link navigate={~p"/users/settings"} class="text-link">Account settings</.link>
                <.link id="header-log-out" href={~p"/users/log-out"} method="delete" class="text-link">Log out</.link>
              </nav>
            </details>
          <% else %>
            <.link navigate={~p"/users/log-in"} class="action action-small">Log in
            <span aria-hidden="true">↗</span></.link>
          <% end %>
        </div>
      </div>
    </header>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={["nav-item", @active && "active"]}
      aria-label={@label}
      title={@label}
      aria-current={@active && "page"}
    >
      <.icon name={@icon} class="size-[18px]" /><span :if={@active}>{@label}</span>
    </.link>
    """
  end
end
