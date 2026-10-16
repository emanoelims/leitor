defmodule LeitorWeb.UserLive.Confirmation do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active="confirmation" class="auth-main">
      <StudyComponents.auth_shell>
        <span class="auth-confirm-icon" aria-hidden="true"><.icon
          name="hero-envelope-open"
          class="size-6"
        /></span>
        <div class="stack gap-2">
          <h2>
            {cond do
              !@user.confirmed_at -> "You're almost home."
              @current_scope -> "Confirm it's you."
              true -> "Welcome back."
            end}
          </h2>
          <p class="muted">
            {if @user.confirmed_at,
              do: gettext("Continue with your email to pick up where you left off."),
              else: gettext("Confirm your email to start saving your words and your progress.")}
          </p>
          <p class="auth-email">{@user.email}</p>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          class="stack gap-3"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <.input field={@form[:token]} type="hidden" />
          <.button
            id="confirm-remember-submit"
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with={gettext("Confirming...")}
            class="action action-primary w-full"
          >
            {gettext("Confirm and stay logged in")}
          </.button>
          <.button
            id="confirm-submit"
            phx-disable-with={gettext("Confirming...")}
            class="action w-full"
          >
            {gettext("Confirm and log in only this time")}
          </.button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          class="stack gap-3"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <.input field={@form[:token]} type="hidden" />
          <%= if @current_scope do %>
            <.button
              id="confirm-session-submit"
              phx-disable-with={gettext("Logging in...")}
              class="action action-primary w-full"
            >
              {gettext("Log in")}
            </.button>
          <% else %>
            <.button
              id="login-remember-submit"
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with={gettext("Logging in...")}
              class="action action-primary w-full"
            >
              {gettext("Keep me logged in on this device")}
            </.button>
            <.button
              id="login-once-submit"
              phx-disable-with={gettext("Logging in...")}
              class="action w-full"
            >
              {gettext("Log me in only this time")}
            </.button>
          <% end %>
        </.form>
        <p :if={!@current_scope} class="muted text-sm">
          {gettext("On a shared device, choose to log in only this time.")}
        </p>
        <.link navigate={~p"/users/log-in"} class="text-link text-sm">{gettext("Back to log in")}</.link>
      </StudyComponents.auth_shell>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Magic link is invalid or it has expired."))
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
