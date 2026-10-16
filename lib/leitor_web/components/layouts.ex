defmodule LeitorWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LeitorWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active, :string, default: "pages"
  attr :class, :any, default: "page"
  attr :style, :string, default: nil
  attr :context_title, :string, default: nil
  attr :context_detail, :string, default: nil
  attr :header_mode, :string, default: "workspace", values: ~w(workspace reader)
  slot :menu, doc: "Workspace context selector; defaults to pages and the combined notebook"
  slot :tabs, doc: "Tabs for the selected workspace context, following its separator"
  slot :tools, doc: "Contextual controls for the current screen"
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :auth_page?, assigns.active in ~w(login register confirmation))

    assigns =
      assign(
        assigns,
        :section_title,
        assigns.context_title ||
          %{
            "pages" => "Pages",
            "library" => "Pages",
            "new" => "New page",
            "notebook" => "Notebook",
            "vocabulary" => "Word jars"
          }[assigns.active] || "Leitor"
      )

    ~H"""
    <a href="#main-content" class="skip-link">{gettext("Skip to content")}</a>
    <header
      id="app-header"
      data-popover-bar
      class={[
        "app-header",
        if(@auth_page?, do: "auth-header", else: "workspace-header"),
        @header_mode == "reader" && "reader-header"
      ]}
    >
      <div class="header-inner">
        <div class="header-left">
          <.link
            :if={@header_mode == "reader"}
            id="page-close"
            navigate={~p"/pages"}
            class="icon-button"
            aria-label={gettext("Close page and return to pages")}
            title={gettext("Back to your pages")}
          ><.icon name="lucide-thin-x" class="size-[18px]" /></.link>
          <.link
            :if={@header_mode != "reader"}
            id="brand-home"
            navigate={if @current_scope, do: ~p"/pages", else: ~p"/users/log-in"}
            class={["brand-home", @auth_page? && "brand-home-wordmark"]}
            aria-label={gettext("Leitor home")}
          >
            <.icon name="leitor-mark" class="brand-symbol" />
            <span :if={@auth_page?} class="brand-wordmark">{gettext("Leitor")}</span>
          </.link>
          <%= if @header_mode == "reader" do %>
            <span class="context-title" title={@section_title}>{@section_title}</span>
          <% else %>
            <%= if @menu != [] do %>
              {render_slot(@menu)}
            <% else %>
              <.workspace_menu :if={@current_scope} active={@active} />
            <% end %>
          <% end %>
          <div :if={@header_mode != "reader" && @tabs != []} id="header-tabs" class="header-tabs">
            <span class="header-tab-divider" aria-hidden="true"></span>
            {render_slot(@tabs)}
          </div>
          <span :if={@context_detail} class="context-detail">{t(@context_detail)}</span>
        </div>
        <div class="header-actions">
          <div
            :if={@tools != []}
            id="header-context-menu"
            class="header-tools"
            role="group"
            aria-label={
              if @header_mode == "reader",
                do: gettext("Page controls"),
                else: gettext("Context controls")
            }
          >
            {render_slot(@tools)}
          </div>
          <%= if @current_scope do %>
            <.popover
              id="account-menu"
              class="account-menu"
              label={gettext("Account menu")}
              title={@current_scope.user.email}
              trigger_class="avatar"
              panel_class="dropdown-menu account-popover"
              menu
            >
              <:trigger><.icon name="lucide-thin-user-round" class="size-[18px]" /></:trigger>
              <div class="dropdown-heading" role="presentation">
                <span>{gettext("Account")}</span>
                <span class="dropdown-account-email">{@current_scope.user.email}</span>
              </div>
              <.dropdown_item
                id="account-preferences"
                navigate={~p"/settings"}
                label={gettext("Preferences")}
                icon="lucide-thin-sliders-horizontal"
                current={@active == "preferences"}
              />
              <.dropdown_item
                id="account-settings"
                navigate={~p"/users/settings"}
                label={gettext("Account settings")}
                icon="lucide-thin-user-round"
                current={@active == "settings"}
              />
              <div class="dropdown-divider" role="separator"></div>
              <.dropdown_item
                id="header-log-out"
                href={~p"/users/log-out"}
                method="delete"
                label={gettext("Log out")}
                icon="lucide-thin-arrow-right"
              />
            </.popover>
          <% else %>
            <%= if @active == "login" do %>
              <span class="auth-header-prompt">{gettext("New here?")}</span>
              <.link navigate={~p"/users/register"} class="text-link auth-header-link">{gettext(
                "Create an account"
              )}
              <.icon name="lucide-thin-arrow-up-right" class="size-3.5" /></.link>
            <% else %>
              <.link navigate={~p"/users/log-in"} class="text-link auth-header-link">{gettext(
                "Log in"
              )}
              <.icon name="lucide-thin-arrow-up-right" class="size-3.5" /></.link>
            <% end %>
          <% end %>
        </div>
      </div>
    </header>
    <main id="main-content" tabindex="-1" class={@class} style={@style}>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the shared workspace context selector.

  Pages and the combined notebook are contexts; creating a page is a separate
  action in the selector. Account controls remain owned by `app/1`.
  """
  attr :active, :string, default: nil

  def workspace_menu(assigns) do
    assigns = assign(assigns, :notebook?, assigns.active == "notebook")

    ~H"""
    <nav id="workspace-menu" class="workspace-menu" aria-label={gettext("Workspace")}>
      <.popover
        id="workspace-context"
        label={gettext("Choose workspace")}
        placement="bottom-start"
        trigger_class="workspace-context-trigger"
        panel_class="dropdown-menu workspace-context-panel"
        menu
      >
        <:trigger>
          <.icon
            name={if @notebook?, do: "lucide-thin-notebook-pen", else: "lucide-thin-layout-grid"}
            class="size-[18px]"
          />
          <span id="workspace-context-label">{if @notebook?,
            do: gettext("Notebook"),
            else: gettext("Pages")}</span>
          <.icon name="lucide-thin-chevrons-down-up" class="size-3" />
        </:trigger>
        <div class="dropdown-heading" role="presentation">{gettext("Workspace")}</div>
        <.dropdown_item
          id="workspace-pages"
          navigate={~p"/pages"}
          label={gettext("Pages")}
          icon="lucide-thin-layout-grid"
          current={!@notebook?}
        />
        <.dropdown_item
          id="workspace-notebook"
          navigate={~p"/notebook"}
          label={gettext("Notebook")}
          icon="lucide-thin-notebook-pen"
          current={@notebook?}
        />
        <div class="dropdown-divider" role="separator"></div>
        <.dropdown_item
          id="page-new"
          navigate={~p"/pages/new"}
          label={gettext("New page")}
          icon="lucide-thin-plus"
        />
      </.popover>
    </nav>
    """
  end

  @doc "Renders search and filters in the shared contextual popover."
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  def workspace_filters(assigns) do
    ~H"""
    <.popover
      id="workspace-filters"
      label={gettext("Search and filters")}
      trigger_class={["workspace-filters-trigger", @active && "active"]}
      panel_class="workspace-filters-panel"
    >
      <:trigger>
        <.icon name="lucide-thin-sliders-horizontal" class="size-4" />
        <span>{gettext("Search & filters")}</span>
        <i :if={@active} class="workspace-filter-indicator" aria-label={gettext("Filters applied")}></i>
      </:trigger>
      {render_slot(@inner_block)}
    </.popover>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
