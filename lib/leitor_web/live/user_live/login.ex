defmodule LeitorWeb.UserLive.Login do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} context_title="Your account">
      <StudyComponents.auth_shell>
        <h2>{if @current_scope, do: "Confirm it's you", else: "Make yourself at home."}</h2>
        <p class="muted">
          {if @current_scope,
            do: "You need to reauthenticate to perform sensitive actions on your account.",
            else: "One email. One magic link. No password to remember."}
        </p>
        <.form for={@form} id="login_form_magic" phx-submit="submit_magic" class="stack">
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            spellcheck="false"
            required
            maxlength="160"
            phx-mounted={JS.focus()}
          />
          <.button id="magic-link-submit" phx-disable-with="Sending your link…">Log in with email
          <.icon name="hero-arrow-right" class="size-4" /></.button>
        </.form>
        <p class="muted text-sm">
          New here? Your first link creates your account. Sign up and log in happen in the same step.
        </p>
        <p :if={local_mail_adapter?()} class="muted text-sm">
          Development email is available in <.link href="/dev/mailbox" class="text-link">the mailbox page</.link>.
        </p>
        <.link navigate={~p"/read"} class="text-link">Keep reading without an account</.link>
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

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    email = if socket.assigns.current_scope, do: socket.assigns.current_scope.user.email, else: String.trim(email)

    user =
      Accounts.get_user_by_email(email) ||
        case Accounts.register_user(%{email: email}) do
          {:ok, user} -> user
          {:error, _changeset} -> Accounts.get_user_by_email(email)
        end

    if user do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is valid, a sign-in link will arrive shortly. Check your inbox."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:leitor, Leitor.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
