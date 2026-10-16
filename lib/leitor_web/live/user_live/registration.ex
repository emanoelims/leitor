defmodule LeitorWeb.UserLive.Registration do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Accounts
  alias Leitor.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active="register" class="auth-main">
      <StudyComponents.auth_shell>
        <div class="auth-form-heading">
          <p class="auth-form-eyebrow">{gettext("Your next chapter")}</p>
          <h2>{gettext("Register for Leitor.")}</h2>
          <p class="muted">{gettext("Start with your email. A private reading space follows.")}</p>
        </div>
        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="email"
            placeholder={gettext("you@example.com")}
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <.button
            id="register-submit"
            phx-disable-with={gettext("Creating account...")}
            variant="primary"
            class="action action-primary w-full"
          >
            {gettext("Create an account")}
          </.button>
        </.form>
        <p class="auth-alternate">
          {gettext("Already have an account?")} <.link navigate={~p"/users/log-in"} class="text-link">{gettext("Log in")}</.link>.
        </p>
      </StudyComponents.auth_shell>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket) when not is_nil(user) do
    {:ok, redirect(socket, to: LeitorWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("An email was sent to %{email}, please access it to confirm your account.", email: user.email)
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
