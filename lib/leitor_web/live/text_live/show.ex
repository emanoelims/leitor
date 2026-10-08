defmodule LeitorWeb.TextLive.Show do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Library
  alias Leitor.Library.Text

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Text {@text.id}
        <:subtitle>This is a text record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/texts"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/texts/#{@text}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit text
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Title">{@text.title}</:item>
        <:item title="Body">{@text.body}</:item>
        <:item title="Position">{@text.position}</:item>
        <:item title="Source">{@text.source}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Library.subscribe_texts(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Text")
     |> assign(:text, Library.get_text!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info({:updated, %Text{id: id} = text}, %{assigns: %{text: %{id: id}}} = socket) do
    {:noreply, assign(socket, :text, text)}
  end

  def handle_info({:deleted, %Text{id: id}}, %{assigns: %{text: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "The current text was deleted.")
     |> push_navigate(to: ~p"/texts")}
  end

  def handle_info({type, %Text{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
