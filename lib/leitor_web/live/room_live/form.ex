defmodule LeitorWeb.RoomLive.Form do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Study
  alias Leitor.Study.Room

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage room records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="room-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:body]} type="textarea" label="Body" />
        <.input field={@form[:position]} type="number" label="Position" />
        <.input field={@form[:invite_code]} type="text" label="Invite code" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Room</.button>
          <.button navigate={return_path(@current_scope, @return_to, @room)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    room = Study.get_room!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Room")
    |> assign(:room, room)
    |> assign(:form, to_form(Study.change_room(socket.assigns.current_scope, room)))
  end

  defp apply_action(socket, :new, _params) do
    room = %Room{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Room")
    |> assign(:room, room)
    |> assign(:form, to_form(Study.change_room(socket.assigns.current_scope, room)))
  end

  @impl true
  def handle_event("validate", %{"room" => room_params}, socket) do
    changeset = Study.change_room(socket.assigns.current_scope, socket.assigns.room, room_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"room" => room_params}, socket) do
    save_room(socket, socket.assigns.live_action, room_params)
  end

  defp save_room(socket, :edit, room_params) do
    case Study.update_room(socket.assigns.current_scope, socket.assigns.room, room_params) do
      {:ok, room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Room updated successfully")
         |> push_navigate(to: return_path(socket.assigns.current_scope, socket.assigns.return_to, room))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_room(socket, :new, room_params) do
    case Study.create_room(socket.assigns.current_scope, room_params) do
      {:ok, room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Room created successfully")
         |> push_navigate(to: return_path(socket.assigns.current_scope, socket.assigns.return_to, room))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _room), do: ~p"/manage/rooms"
  defp return_path(_scope, "show", room), do: ~p"/manage/rooms/#{room}"
end
