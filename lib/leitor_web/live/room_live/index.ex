defmodule LeitorWeb.RoomLive.Index do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Study

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Rooms
        <:actions>
          <.button variant="primary" navigate={~p"/manage/rooms/new"}>
            <.icon name="hero-plus" /> New Room
          </.button>
        </:actions>
      </.header>

      <.table
        id="rooms"
        rows={@streams.rooms}
        row_click={fn {_id, room} -> JS.navigate(~p"/manage/rooms/#{room}") end}
      >
        <:col :let={{_id, room}} label="Title">{room.title}</:col>
        <:col :let={{_id, room}} label="Body">{room.body}</:col>
        <:col :let={{_id, room}} label="Position">{room.position}</:col>
        <:col :let={{_id, room}} label="Invite code">{room.invite_code}</:col>
        <:action :let={{_id, room}}>
          <div class="sr-only">
            <.link navigate={~p"/manage/rooms/#{room}"}>Show</.link>
          </div>
          <.link navigate={~p"/manage/rooms/#{room}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, room}}>
          <.link
            phx-click={JS.push("delete", value: %{id: room.id}) |> hide("##{id}")}
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
      Study.subscribe_rooms(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Rooms")
     |> stream(:rooms, list_rooms(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    room = Study.get_room!(socket.assigns.current_scope, id)
    {:ok, _} = Study.delete_room(socket.assigns.current_scope, room)

    {:noreply, stream_delete(socket, :rooms, room)}
  end

  @impl true
  def handle_info({type, %Leitor.Study.Room{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, stream(socket, :rooms, list_rooms(socket.assigns.current_scope), reset: true)}
  end

  defp list_rooms(current_scope) do
    Study.list_rooms(current_scope)
  end
end
