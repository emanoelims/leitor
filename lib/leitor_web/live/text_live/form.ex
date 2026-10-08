defmodule LeitorWeb.TextLive.Form do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Library
  alias Leitor.Library.Text

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage text records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="text-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:body]} type="textarea" label="Body" />
        <.input field={@form[:position]} type="number" label="Position" />
        <.input field={@form[:source]} type="text" label="Source" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Text</.button>
          <.button navigate={return_path(@current_scope, @return_to, @text)}>Cancel</.button>
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
    text = Library.get_text!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Text")
    |> assign(:text, text)
    |> assign(:form, to_form(Library.change_text(socket.assigns.current_scope, text)))
  end

  defp apply_action(socket, :new, _params) do
    text = %Text{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Text")
    |> assign(:text, text)
    |> assign(:form, to_form(Library.change_text(socket.assigns.current_scope, text)))
  end

  @impl true
  def handle_event("validate", %{"text" => text_params}, socket) do
    changeset = Library.change_text(socket.assigns.current_scope, socket.assigns.text, text_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"text" => text_params}, socket) do
    save_text(socket, socket.assigns.live_action, text_params)
  end

  defp save_text(socket, :edit, text_params) do
    case Library.update_text(socket.assigns.current_scope, socket.assigns.text, text_params) do
      {:ok, text} ->
        {:noreply,
         socket
         |> put_flash(:info, "Text updated successfully")
         |> push_navigate(to: return_path(socket.assigns.current_scope, socket.assigns.return_to, text))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_text(socket, :new, text_params) do
    case Library.create_text(socket.assigns.current_scope, text_params) do
      {:ok, text} ->
        {:noreply,
         socket
         |> put_flash(:info, "Text created successfully")
         |> push_navigate(to: return_path(socket.assigns.current_scope, socket.assigns.return_to, text))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _text), do: ~p"/texts"
  defp return_path(_scope, "show", text), do: ~p"/texts/#{text}"
end
