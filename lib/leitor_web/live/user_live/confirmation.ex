defmodule LeitorWeb.UserLive.Confirmation do
  use LeitorWeb, :live_view

  alias Leitor.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>Welcome {@user.email}</.header>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
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
            phx-disable-with="Confirming..."
            class="inline-flex w-full items-center justify-center rounded-lg bg-slate-900 px-4 py-2.5 font-semibold text-white transition hover:bg-slate-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900 disabled:cursor-wait disabled:opacity-60"
          >
            Confirm and stay logged in
          </.button>
          <.button
            id="confirm-submit"
            phx-disable-with="Confirming..."
            class="mt-2 inline-flex w-full items-center justify-center rounded-lg border border-slate-300 px-4 py-2.5 font-semibold text-slate-700 transition hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900 disabled:cursor-wait disabled:opacity-60"
          >
            Confirm and log in only this time
          </.button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <.input field={@form[:token]} type="hidden" />
          <%= if @current_scope do %>
            <.button
              id="confirm-session-submit"
              phx-disable-with="Logging in..."
              class="inline-flex w-full items-center justify-center rounded-lg bg-slate-900 px-4 py-2.5 font-semibold text-white transition hover:bg-slate-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900 disabled:cursor-wait disabled:opacity-60"
            >
              Log in
            </.button>
          <% else %>
            <.button
              id="login-remember-submit"
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Logging in..."
              class="inline-flex w-full items-center justify-center rounded-lg bg-slate-900 px-4 py-2.5 font-semibold text-white transition hover:bg-slate-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900 disabled:cursor-wait disabled:opacity-60"
            >
              Keep me logged in on this device
            </.button>
            <.button
              id="login-once-submit"
              phx-disable-with="Logging in..."
              class="mt-2 inline-flex w-full items-center justify-center rounded-lg border border-slate-300 px-4 py-2.5 font-semibold text-slate-700 transition hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900 disabled:cursor-wait disabled:opacity-60"
            >
              Log me in only this time
            </.button>
          <% end %>
        </.form>

        <p
          :if={!@user.confirmed_at}
          class="mt-8 rounded-lg border border-slate-200 p-4 text-sm text-slate-600"
        >
          Tip: If you prefer passwords, you can enable them in the user settings.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
