defmodule LeitorWeb.AttemptLive.Show do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning
  alias Leitor.Learning.Attempt

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Attempt {@attempt.id}
        <:subtitle>This is a attempt record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/attempts"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/attempts/#{@attempt}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit attempt
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Kind">{@attempt.kind}</:item>
        <:item title="Content">{@attempt.content}</:item>
        <:item title="Result">{Jason.encode!(@attempt.result)}</:item>
        <:item title="Duration">{@attempt.duration}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Learning.subscribe_attempts(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Attempt")
     |> assign(:attempt, Learning.get_attempt!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info({:updated, %Attempt{id: id} = attempt}, %{assigns: %{attempt: %{id: id}}} = socket) do
    {:noreply, assign(socket, :attempt, attempt)}
  end

  def handle_info({:deleted, %Attempt{id: id}}, %{assigns: %{attempt: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "The current attempt was deleted.")
     |> push_navigate(to: ~p"/attempts")}
  end

  def handle_info({type, %Attempt{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
