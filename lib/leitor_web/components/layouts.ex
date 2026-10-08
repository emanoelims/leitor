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

  attr :active, :string, default: "read"
  attr :class, :string, default: "page"
  attr :context_title, :string, default: nil
  attr :context_detail, :string, default: nil
  attr :speech, :string, default: nil
  slot :header_controls
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <LeitorWeb.Shell.header
      current_scope={@current_scope}
      active={@active}
      context_title={@context_title}
      context_detail={@context_detail}
      speech={@speech}
    >
      <:controls>{render_slot(@header_controls)}</:controls>
    </LeitorWeb.Shell.header>
    <main id="main-content" tabindex="-1" class={@class}>
      {render_slot(@inner_block)}
    </main>

    <aside
      id="speech-status"
      class="speech-notice notice row"
      role="status"
      hidden
      phx-update="ignore"
    >
      <p></p><button
        type="button"
        class="icon-button"
        aria-label="Dismiss audio notice"
        phx-click={JS.set_attribute({"hidden", ""}, to: "#speech-status")}
      ><.icon name="hero-x-mark" class="size-4" /></button>
    </aside>
    <.flash_group flash={@flash} />
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
