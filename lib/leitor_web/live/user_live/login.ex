defmodule LeitorWeb.UserLive.Login do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active="login" class="auth-main">
      <StudyComponents.auth_shell>
        <div class="auth-form-heading">
          <p class="auth-form-eyebrow">
            {if @current_scope, do: gettext("A quick check"), else: gettext("Welcome to Leitor")}
          </p>
          <h2>
            {if @current_scope,
              do: gettext("Confirm it's you."),
              else: gettext("Pick up a good thought.")}
          </h2>
          <p class="muted">
            {if @current_scope,
              do: gettext("You need to reauthenticate to continue. We’ll send a link to your email."),
              else: gettext("A link in your inbox. A quiet place to read.")}
          </p>
        </div>
        <.form for={@form} id="login_form_magic" phx-submit="submit_magic" class="stack">
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="email"
            placeholder={gettext("you@example.com")}
            spellcheck="false"
            required
            maxlength="160"
            phx-mounted={JS.focus()}
          />
          <.button
            id="magic-link-submit"
            class="action action-primary auth-submit"
            phx-disable-with={gettext("Sending your link…")}
          >{gettext("Log in with email")} <.icon name="lucide-thin-arrow-right" class="size-4" /></.button>
        </.form>
        <p class="auth-alternate">
          {gettext("Don't have an account?")} <.link navigate={~p"/users/register"} class="text-link">{gettext("Sign up")}</.link>.
        </p>
      </StudyComponents.auth_shell>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form)}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    email = if socket.assigns.current_scope, do: socket.assigns.current_scope.user.email, else: String.trim(email)

    user = Accounts.get_user_by_email(email)

    if user do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      gettext("If your email is valid, a sign-in link will arrive shortly. Check your inbox.")

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end
end
