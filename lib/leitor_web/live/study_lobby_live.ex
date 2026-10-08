defmodule LeitorWeb.StudyLobbyLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Library.Reading
  alias Leitor.Study

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Study.subscribe_rooms(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(
       page_title: "Study together",
       form: to_form(%{"title" => "", "body" => Enum.map_join(Reading.sample(), " ", & &1.body)}, as: :room),
       join_form: to_form(%{}, as: :invitation)
     )
     |> stream(:rooms, Study.list_rooms(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("create", %{"room" => attrs}, socket) do
    case Study.open_room(socket.assigns.current_scope, attrs) do
      {:ok, room} -> {:noreply, push_navigate(socket, to: ~p"/rooms/#{room.invite_code}")}
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset, as: :room))}
    end
  end

  def handle_event("join", %{"invitation" => %{"code" => value}}, socket) do
    code = value |> String.trim() |> String.split("/") |> List.last()

    case Study.join_room(socket.assigns.current_scope, code) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{room.invite_code}")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "This invitation is unavailable. Ask the host for a new link.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    room = Study.get_room!(socket.assigns.current_scope, id)
    {:ok, _} = Study.delete_room(socket.assigns.current_scope, room)
    {:noreply, stream_delete(socket, :rooms, room)}
  end

  @impl true
  def handle_info({event, room}, socket) when event in [:created, :updated],
    do: {:noreply, stream_insert(socket, :rooms, room)}

  def handle_info({:deleted, room}, socket), do: {:noreply, stream_delete(socket, :rooms, room)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active="rooms">
      <StudyComponents.page_heading
        title="Better together."
        subtitle="Invite a friend, read at the same pace, and talk through what you notice."
        eyebrow="Study rooms"
      />
      <div class="two-column">
        <section class="card stack">
          <h2>Start a reading room</h2>
          <p class="muted">
            You control the reading position. Everyone with your private invitation can join after signing in.
          </p>
          <.form for={@form} id="room-form" phx-submit="create" class="stack">
            <.input
              field={@form[:title]}
              label="Room name"
              required
              maxlength="180"
              placeholder="Thursday reading club"
            />
            <.input
              field={@form[:body]}
              type="textarea"
              label="Text to read together"
              required
              maxlength="300000"
              rows="8"
            />
            <.button id="create-room" phx-disable-with="Opening…">Open room</.button>
          </.form>
        </section>
        <div class="stack">
          <section class="card stack">
            <h2>Have an invitation?</h2>
            <.form for={@join_form} id="join-room-form" phx-submit="join" class="stack">
              <.input
                field={@join_form[:code]}
                label="Invitation link or code"
                required
                autocomplete="off"
              />
              <.button>Join room</.button>
            </.form>
          </section>
          <section class="stack">
            <h2>Your rooms</h2>
            <div id="owned-rooms" phx-update="stream" class="stack">
              <div id="no-rooms" class="hidden only:block">
                <StudyComponents.empty_state
                  title="Your next reading club starts here."
                  body="Open a room and share its link with a friend."
                />
              </div>
              <article :for={{id, room} <- @streams.rooms} id={id} class="card row between">
                <.link navigate={~p"/rooms/#{room.invite_code}"} class="text-link">{room.title}</.link>
                <button
                  id={"close-#{room.id}"}
                  type="button"
                  phx-click="delete"
                  phx-value-id={room.id}
                  data-confirm="Close this room for everyone?"
                  class="action action-small"
                >Close room</button>
              </article>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
