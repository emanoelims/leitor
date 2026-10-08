defmodule LeitorWeb.RoomLive.Show do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Study
  alias Leitor.Study.Room

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Room {@room.id}
        <:subtitle>This is a room record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/manage/rooms"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/manage/rooms/#{@room}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit room
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Title">{@room.title}</:item>
        <:item title="Body">{@room.body}</:item>
        <:item title="Position">{@room.position}</:item>
        <:item title="Invite code">{@room.invite_code}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Study.subscribe_rooms(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Room")
     |> assign(:room, Study.get_room!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info({:updated, %Room{id: id} = room}, %{assigns: %{room: %{id: id}}} = socket) do
    {:noreply, assign(socket, :room, room)}
  end

  def handle_info({:deleted, %Room{id: id}}, %{assigns: %{room: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "The current room was deleted.")
     |> push_navigate(to: ~p"/manage/rooms")}
  end

  def handle_info({type, %Room{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
