defmodule LeitorWeb.EntryLive.Show do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning
  alias Leitor.Learning.Entry

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Entry {@entry.id}
        <:subtitle>This is a entry record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/entries"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/entries/#{@entry}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit entry
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Term">{@entry.term}</:item>
        <:item title="Meaning">{@entry.meaning}</:item>
        <:item title="Category">{@entry.category}</:item>
        <:item title="Context">{@entry.context}</:item>
        <:item title="Status">{@entry.status}</:item>
        <:item title="Interval">{@entry.interval}</:item>
        <:item title="Due at">{@entry.due_at}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Learning.subscribe_entries(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Entry")
     |> assign(:entry, Learning.get_entry!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info({:updated, %Entry{id: id} = entry}, %{assigns: %{entry: %{id: id}}} = socket) do
    {:noreply, assign(socket, :entry, entry)}
  end

  def handle_info({:deleted, %Entry{id: id}}, %{assigns: %{entry: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "The current entry was deleted.")
     |> push_navigate(to: ~p"/entries")}
  end

  def handle_info({type, %Entry{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
