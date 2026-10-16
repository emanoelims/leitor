defmodule LeitorWeb.PreferencesLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Accounts
  alias Leitor.Accounts.Preferences
  alias Leitor.Accounts.Scope
  alias Leitor.Language

  @impl true
  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Preferences"),
       form: to_form(Accounts.change_preferences(socket.assigns.current_scope))
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="preferences"
      class="page preferences-workspace"
    >
      <:tools>
        <button
          id="save-preferences"
          aria-label={gettext("Save preferences")}
          title={gettext("Save preferences")}
          type="submit"
          form="preferences-form"
          class="workspace-header-action workspace-header-primary"
          phx-disable-with={gettext("Saving…")}
        >
          <span>{gettext("Save preferences")}</span> <.icon name="lucide-thin-check" class="size-4" />
        </button>
      </:tools>
      <header class="preferences-heading">
        <p class="eyebrow">{gettext("Make yourself at home")}</p>
        <h1>{gettext("Preferences")}</h1>
        <p>{gettext("Your language, your reading companion.")}</p>
      </header>
      <.form for={@form} id="preferences-form" phx-change="validate" phx-submit="save">
        <.inputs_for :let={preferences} field={@form[:preferences]}>
          <section class="preferences-section">
            <div class="preferences-section-heading">
              <.icon name="lucide-languages" class="size-5" /><div>
                <h2>{gettext("Languages")}</h2><p>
                  {gettext("The interface and AI can speak different languages.")}
                </p>
              </div>
            </div>
            <div class="preferences-fields">
              <.input
                id="preferences-locale"
                field={preferences[:locale]}
                type="select"
                label={gettext("Application language")}
                options={LeitorWeb.I18n.options(Preferences.languages())}
              />
              <div>
                <.input
                  id="preferences-ai-locale"
                  field={preferences[:ai_locale]}
                  type="select"
                  label={gettext("AI response language")}
                  options={LeitorWeb.I18n.options(Preferences.response_languages())}
                /><p class="preferences-help">
                  {gettext("An explicit language request takes priority.")}
                </p>
              </div>
            </div>
          </section>
          <section class="preferences-section">
            <div class="preferences-section-heading">
              <.icon name="lucide-feather" class="size-5" /><div>
                <h2>{gettext("Claude models")}</h2><p>
                  {gettext("Choose a model for each kind of work.")}
                </p>
              </div>
            </div>
            <div class="preferences-fields">
              <div>
                <.input
                  id="preferences-reading-model"
                  field={preferences[:reading_model]}
                  type="select"
                  label={gettext("Reading and explanations")}
                  options={LeitorWeb.I18n.options(Preferences.models())}
                /><p class="preferences-help">
                  {gettext("Definitions, explanations, questions and follow-ups.")}
                </p>
              </div>
              <div>
                <.input
                  id="preferences-writing-model"
                  field={preferences[:writing_model]}
                  type="select"
                  label={gettext("Writing and generation")}
                  options={LeitorWeb.I18n.options(Preferences.models())}
                /><p class="preferences-help">{gettext("Text generated from the / menu.")}</p>
              </div>
            </div>
            <p class="preferences-connection">
              {gettext("Uses the Claude connection already configured for this application.")}
            </p>
            <dl class="preferences-defaults">
              <div>
                <dt>{gettext("Reading default")}</dt><dd>
                  {String.replace_prefix(Language.model(:analysis), "anthropic:", "")}
                </dd>
              </div><div>
                <dt>{gettext("Writing default")}</dt><dd>
                  {String.replace_prefix(Language.model(:feedback), "anthropic:", "")}
                </dd>
              </div>
            </dl>
          </section>
        </.inputs_for>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"user" => %{"preferences" => attrs}}, socket) do
    form = socket.assigns.current_scope |> Accounts.change_preferences(attrs) |> to_form(action: :validate)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"user" => %{"preferences" => attrs}}, socket) do
    case Accounts.update_preferences(socket.assigns.current_scope, attrs) do
      {:ok, user} ->
        Gettext.put_locale(LeitorWeb.Gettext, user.preferences.locale)

        {:noreply,
         socket
         |> assign(current_scope: Scope.for_user(user))
         |> put_flash(:info, gettext("Preferences saved."))
         |> redirect(to: ~p"/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :update))}
    end
  end
end
