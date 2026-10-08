defmodule LeitorWeb.AttemptLive.Index do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Attempts
        <:actions>
          <.button variant="primary" navigate={~p"/attempts/new"}>
            <.icon name="hero-plus" /> New Attempt
          </.button>
        </:actions>
      </.header>

      <.table
        id="attempts"
        rows={@streams.attempts}
        row_click={fn {_id, attempt} -> JS.navigate(~p"/attempts/#{attempt}") end}
      >
        <:col :let={{_id, attempt}} label="Kind">{attempt.kind}</:col>
        <:col :let={{_id, attempt}} label="Content">{attempt.content}</:col>
        <:col :let={{_id, attempt}} label="Result">{Jason.encode!(attempt.result)}</:col>
        <:col :let={{_id, attempt}} label="Duration">{attempt.duration}</:col>
        <:action :let={{_id, attempt}}>
          <div class="sr-only">
            <.link navigate={~p"/attempts/#{attempt}"}>Show</.link>
          </div>
          <.link navigate={~p"/attempts/#{attempt}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, attempt}}>
          <.link
            phx-click={JS.push("delete", value: %{id: attempt.id}) |> hide("##{id}")}
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
      Learning.subscribe_attempts(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Attempts")
     |> stream(:attempts, list_attempts(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    attempt = Learning.get_attempt!(socket.assigns.current_scope, id)
    {:ok, _} = Learning.delete_attempt(socket.assigns.current_scope, attempt)

    {:noreply, stream_delete(socket, :attempts, attempt)}
  end

  @impl true
  def handle_info({type, %Leitor.Learning.Attempt{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, stream(socket, :attempts, list_attempts(socket.assigns.current_scope), reset: true)}
  end

  defp list_attempts(current_scope) do
    Learning.list_attempts(current_scope)
  end
end
