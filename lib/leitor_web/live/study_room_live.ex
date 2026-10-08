defmodule LeitorWeb.StudyRoomLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Library.Reading
  alias Leitor.Study
  alias LeitorWeb.Presence

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    scope = socket.assigns.current_scope

    result = if connected?(socket), do: Study.subscribe_room(scope, code), else: Study.join_room(scope, code)

    case result do
      {:ok, room} ->
        if connected?(socket) do
          {:ok, _} = Presence.track(self(), Study.topic(room), scope.user.id, %{name: Study.participant_name(scope)})
        end

        sentences = Reading.prepare(room.body)
        room = %{room | position: min(room.position, length(sentences) - 1)}

        {:ok,
         socket
         |> assign(
           room: room,
           sentences: sentences,
           sentence: Enum.at(sentences, room.position),
           host?: room.user_id == scope.user.id,
           participant_count: 0,
           page_title: room.title,
           message_form: to_form(%{"body" => ""}, as: :message),
           last_message_at: nil
         )
         |> stream(:messages, [])
         |> stream(:participants, [])
         |> refresh_presence()}

      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, "This room is closed or the invitation is invalid.") |> push_navigate(to: ~p"/rooms")}
    end
  end

  @impl true
  def handle_event("move", %{"direction" => direction}, socket) when direction in ["next", "previous"] do
    step = if direction == "next", do: :next, else: :previous

    case Study.advance_room(socket.assigns.current_scope, socket.assigns.room.invite_code, step) do
      {:ok, room} -> {:noreply, set_room(socket, room)}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, "The host controls the shared reading position.")}
      {:error, :not_found} -> {:noreply, push_navigate(socket, to: ~p"/rooms")}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "The reading position could not be updated.")}
    end
  end

  def handle_event("message", %{"message" => %{"body" => body}}, socket) do
    now = System.monotonic_time(:millisecond)

    if socket.assigns.last_message_at && now - socket.assigns.last_message_at < 1000 do
      {:noreply, put_flash(socket, :error, "Please wait a moment before sending another message.")}
    else
      case Study.send_message(socket.assigns.current_scope, socket.assigns.room.invite_code, body) do
        :ok ->
          {:noreply, assign(socket, message_form: to_form(%{"body" => ""}, as: :message), last_message_at: now)}

        {:error, :not_found} ->
          {:noreply, push_navigate(socket, to: ~p"/rooms")}

        {:error, :invalid_message} ->
          {:noreply, put_flash(socket, :error, "Write a message between 1 and 500 characters.")}
      end
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket), do: {:noreply, refresh_presence(socket)}
  def handle_info({:room_updated, room}, socket), do: {:noreply, set_room(socket, room)}

  def handle_info({:room_message, message}, socket),
    do: {:noreply, stream_insert(socket, :messages, message, at: -1, limit: -50)}

  def handle_info(:room_closed, socket),
    do: {:noreply, socket |> put_flash(:info, "The host closed this room.") |> push_navigate(to: ~p"/rooms")}

  defp set_room(socket, room) do
    sentences = Reading.prepare(room.body)
    room = %{room | position: min(room.position, length(sentences) - 1)}
    assign(socket, room: room, sentences: sentences, sentence: Enum.at(sentences, room.position))
  end

  defp refresh_presence(socket) do
    participants =
      socket.assigns.room
      |> Study.topic()
      |> Presence.list()
      |> Enum.map(fn {id, %{metas: [meta | _]}} -> %{id: id, name: meta.name} end)
      |> Enum.sort_by(& &1.name)

    socket |> assign(participant_count: length(participants)) |> stream(:participants, participants, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active="rooms">
      <StudyComponents.page_heading
        title={@room.title}
        subtitle="One sentence. A few curious minds."
        eyebrow="Live reading room"
      >
        <:actions><.link navigate={~p"/rooms"} class="action">All rooms</.link></:actions>
      </StudyComponents.page_heading>
      <div class="two-column">
        <section class="card stack">
          <div class="row between">
            <span class="eyebrow">Sentence {@room.position + 1} / {length(@sentences)}</span><span class="badge">{if @host?,
              do: "You are hosting",
              else: "Following the host"}</span>
          </div>
          <StudyComponents.progress
            value={@room.position + 1}
            max={length(@sentences)}
            label="Shared reading progress"
          />
          <p id="shared-sentence" class="reading-sentence" aria-live="polite">{@sentence.body}</p>
          <button
            id="room-listen"
            class="action"
            phx-click={JS.dispatch("leitor:speak", detail: %{text: @sentence.body, rate: 0.85})}
          ><.icon name="hero-speaker-wave" class="size-4" /> Listen</button>
          <div class="row between">
            <button
              id="room-previous"
              class="action"
              phx-click="move"
              phx-value-direction="previous"
              disabled={!@host? || @room.position == 0}
            >Previous sentence</button>
            <button
              id="room-next"
              class="action action-primary"
              phx-click="move"
              phx-value-direction="next"
              disabled={!@host? || @room.position >= length(@sentences) - 1}
            >Next sentence</button>
          </div>
          <p :if={!@host?} class="muted">
            The host chooses the sentence. Your audio playback is personal.
          </p>
          <div class="divider"></div>
          <label for="room-invitation" class="field-label">Private invitation</label>
          <input
            id="room-invitation"
            class="field mono"
            readonly
            value={url(~p"/rooms/#{@room.invite_code}")}
          />
          <p class="muted">
            Share with people you want to invite. Closing the room revokes this link.
          </p>
        </section>
        <aside class="stack">
          <section class="card stack">
            <h2>{@participant_count} online</h2>
            <ul id="room-participants" phx-update="stream" class="row wrap" aria-live="polite">
              <li :for={{id, person} <- @streams.participants} id={id} class="badge">
                {person.name}{if person.id == @room.user_id, do: " · host"}
              </li>
            </ul>
          </section>
          <section class="card stack">
            <h2>Room conversation</h2>
            <p class="muted">Messages are live and temporary. Your email stays private.</p>
            <div
              id="room-messages"
              phx-update="stream"
              class="stack"
              role="log"
              aria-label="Room messages"
              aria-live="polite"
            >
              <p id="no-messages" class="hidden only:block muted">
                Say hello or share a question about this sentence.
              </p>
              <article :for={{id, message} <- @streams.messages} id={id}>
                <span class="eyebrow">{message.name}</span><p class="break-words">{message.body}</p>
              </article>
            </div>
            <.form for={@message_form} id="message-form" phx-submit="message" class="stack">
              <.input
                field={@message_form[:body]}
                label="Message"
                required
                maxlength="500"
                autocomplete="off"
              />
              <.button phx-disable-with="Sending…">Send message</.button>
            </.form>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
