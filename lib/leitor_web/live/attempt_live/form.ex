defmodule LeitorWeb.AttemptLive.Form do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning
  alias Leitor.Learning.Attempt

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage attempt records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="attempt-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:kind]} type="text" label="Kind" />
        <.input field={@form[:content]} type="textarea" label="Content" />
        <.input field={@form[:duration]} type="number" label="Duration" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Attempt</.button>
          <.button navigate={return_path(@current_scope, @return_to, @attempt)}>Cancel</.button>
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
    attempt = Learning.get_attempt!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Attempt")
    |> assign(:attempt, attempt)
    |> assign(:form, to_form(Learning.change_attempt(socket.assigns.current_scope, attempt)))
  end

  defp apply_action(socket, :new, _params) do
    attempt = %Attempt{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Attempt")
    |> assign(:attempt, attempt)
    |> assign(:form, to_form(Learning.change_attempt(socket.assigns.current_scope, attempt)))
  end

  @impl true
  def handle_event("validate", %{"attempt" => attempt_params}, socket) do
    changeset = Learning.change_attempt(socket.assigns.current_scope, socket.assigns.attempt, attempt_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"attempt" => attempt_params}, socket) do
    save_attempt(socket, socket.assigns.live_action, attempt_params)
  end

  defp save_attempt(socket, :edit, attempt_params) do
    case Learning.update_attempt(socket.assigns.current_scope, socket.assigns.attempt, attempt_params) do
      {:ok, attempt} ->
        {:noreply,
         socket
         |> put_flash(:info, "Attempt updated successfully")
         |> push_navigate(to: return_path(socket.assigns.current_scope, socket.assigns.return_to, attempt))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_attempt(socket, :new, attempt_params) do
    case Learning.create_attempt(socket.assigns.current_scope, attempt_params) do
      {:ok, attempt} ->
        {:noreply,
         socket
         |> put_flash(:info, "Attempt created successfully")
         |> push_navigate(to: return_path(socket.assigns.current_scope, socket.assigns.return_to, attempt))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _attempt), do: ~p"/attempts"
  defp return_path(_scope, "show", attempt), do: ~p"/attempts/#{attempt}"
end
