defmodule LeitorWeb.TextLive.Index do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Library

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Texts
        <:actions>
          <.button variant="primary" navigate={~p"/texts/new"}>
            <.icon name="hero-plus" /> New Text
          </.button>
        </:actions>
      </.header>

      <.table
        id="texts"
        rows={@streams.texts}
        row_click={fn {_id, text} -> JS.navigate(~p"/texts/#{text}") end}
      >
        <:col :let={{_id, text}} label="Title">{text.title}</:col>
        <:col :let={{_id, text}} label="Body">{text.body}</:col>
        <:col :let={{_id, text}} label="Position">{text.position}</:col>
        <:col :let={{_id, text}} label="Source">{text.source}</:col>
        <:action :let={{_id, text}}>
          <div class="sr-only">
            <.link navigate={~p"/texts/#{text}"}>Show</.link>
          </div>
          <.link navigate={~p"/texts/#{text}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, text}}>
          <.link
            phx-click={JS.push("delete", value: %{id: text.id}) |> hide("##{id}")}
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
      Library.subscribe_texts(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Texts")
     |> stream(:texts, list_texts(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    text = Library.get_text!(socket.assigns.current_scope, id)
    {:ok, _} = Library.delete_text(socket.assigns.current_scope, text)

    {:noreply, stream_delete(socket, :texts, text)}
  end

  @impl true
  def handle_info({type, %Leitor.Library.Text{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, stream(socket, :texts, list_texts(socket.assigns.current_scope), reset: true)}
  end

  defp list_texts(current_scope) do
    Library.list_texts(current_scope)
  end
end
