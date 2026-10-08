defmodule LeitorWeb.EntryLive.Index do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Entries
        <:actions>
          <.button variant="primary" navigate={~p"/entries/new"}>
            <.icon name="hero-plus" /> New Entry
          </.button>
        </:actions>
      </.header>

      <.table
        id="entries"
        rows={@streams.entries}
        row_click={fn {_id, entry} -> JS.navigate(~p"/entries/#{entry}") end}
      >
        <:col :let={{_id, entry}} label="Term">{entry.term}</:col>
        <:col :let={{_id, entry}} label="Meaning">{entry.meaning}</:col>
        <:col :let={{_id, entry}} label="Category">{entry.category}</:col>
        <:col :let={{_id, entry}} label="Context">{entry.context}</:col>
        <:col :let={{_id, entry}} label="Status">{entry.status}</:col>
        <:col :let={{_id, entry}} label="Interval">{entry.interval}</:col>
        <:col :let={{_id, entry}} label="Due at">{entry.due_at}</:col>
        <:action :let={{_id, entry}}>
          <div class="sr-only">
            <.link navigate={~p"/entries/#{entry}"}>Show</.link>
          </div>
          <.link navigate={~p"/entries/#{entry}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, entry}}>
          <.link
            phx-click={JS.push("delete", value: %{id: entry.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Learning.subscribe_entries(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Entries")
     |> stream(:entries, list_entries(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    entry = Learning.get_entry!(socket.assigns.current_scope, id)
    {:ok, _} = Learning.delete_entry(socket.assigns.current_scope, entry)

    {:noreply, stream_delete(socket, :entries, entry)}
  end

  @impl true
  def handle_info({type, %Leitor.Learning.Entry{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, stream(socket, :entries, list_entries(socket.assigns.current_scope), reset: true)}
  end

  defp list_entries(current_scope) do
    Learning.list_entries(current_scope)
  end
end
