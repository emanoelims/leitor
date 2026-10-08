defmodule LeitorWeb.EntryLive.Form do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning
  alias Leitor.Learning.Entry

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage entry records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="entry-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:term]} type="text" label="Term" />
        <.input field={@form[:meaning]} type="text" label="Meaning" />
        <.input field={@form[:category]} type="text" label="Category" />
        <.input field={@form[:context]} type="textarea" label="Context" />
        <.input field={@form[:status]} type="text" label="Status" />
        <.input field={@form[:interval]} type="number" label="Interval" />
        <.input field={@form[:due_at]} type="datetime-local" label="Due at" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Entry</.button>
          <.button navigate={return_path(@current_scope, @return_to, @entry)}>Cancel</.button>
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
    entry = Learning.get_entry!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Entry")
    |> assign(:entry, entry)
    |> assign(:form, to_form(Learning.change_entry(socket.assigns.current_scope, entry)))
  end

  defp apply_action(socket, :new, _params) do
    entry = %Entry{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Entry")
    |> assign(:entry, entry)
    |> assign(:form, to_form(Learning.change_entry(socket.assigns.current_scope, entry)))
  end

  @impl true
  def handle_event("validate", %{"entry" => entry_params}, socket) do
    changeset = Learning.change_entry(socket.assigns.current_scope, socket.assigns.entry, entry_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"entry" => entry_params}, socket) do
    save_entry(socket, socket.assigns.live_action, entry_params)
  end

  defp save_entry(socket, :edit, entry_params) do
    case Learning.update_entry(socket.assigns.current_scope, socket.assigns.entry, entry_params) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Entry updated successfully")
         |> push_navigate(to: return_path(socket.assigns.current_scope, socket.assigns.return_to, entry))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_entry(socket, :new, entry_params) do
    case Learning.create_entry(socket.assigns.current_scope, entry_params) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Entry created successfully")
         |> push_navigate(to: return_path(socket.assigns.current_scope, socket.assigns.return_to, entry))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _entry), do: ~p"/entries"
  defp return_path(_scope, "show", entry), do: ~p"/entries/#{entry}"
end
