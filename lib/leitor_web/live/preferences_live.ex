defmodule LeitorWeb.PreferencesLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Accounts
  alias Leitor.Accounts.Preferences
  alias Leitor.Accounts.Scope
  alias Leitor.AI
  alias Leitor.AI.Credential

  @impl true
  def mount(_, _, socket) do
    credentials = AI.credentials(socket.assigns.current_scope)

    {:ok,
     socket
     |> stream(:credentials, credentials)
     |> assign(
       page_title: gettext("Preferences"),
       form: to_form(Accounts.change_preferences(socket.assigns.current_scope)),
       credentials: credentials,
       usage: AI.usage(socket.assigns.current_scope),
       credential_form: blank_credential_form()
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
                  options={LeitorWeb.I18n.options(available_models(@credentials))}
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
                  options={LeitorWeb.I18n.options(available_models(@credentials))}
                /><p class="preferences-help">{gettext("Text generated from the / menu.")}</p>
              </div>
            </div>
            <p class="preferences-connection">
              {gettext(
                "The application key uses Haiku only. Add your own Anthropic key to unlock other Claude models."
              )}
            </p>
            <dl class="preferences-defaults">
              <div>
                <dt>{gettext("Reading default")}</dt><dd>
                  {String.replace_prefix(AI.shared_model(), "anthropic:", "")}
                </dd>
              </div><div>
                <dt>{gettext("Writing default")}</dt><dd>
                  {String.replace_prefix(AI.shared_model(), "anthropic:", "")}
                </dd>
              </div>
            </dl>
          </section>
          <section class="preferences-section">
            <div class="preferences-section-heading">
              <.icon name="lucide-image" class="size-5" /><div>
                <h2>{gettext("Images and voice")}</h2>
                <p>
                  {gettext(
                    "SVG is active now. Provider images and narration will be enabled separately; these choices are saved for then."
                  )}
                </p>
              </div>
            </div>
            <div class="preferences-fields">
              <.input
                id="preferences-image-model"
                field={preferences[:image_model]}
                type="select"
                label={gettext("Illustration model")}
                options={LeitorWeb.I18n.options(Preferences.image_models())}
              />
              <.input
                id="preferences-speech-model"
                field={preferences[:speech_model]}
                type="select"
                label={gettext("Narration model")}
                options={LeitorWeb.I18n.options(Preferences.speech_models())}
              />
              <.input
                id="preferences-speech-voice"
                field={preferences[:speech_voice]}
                label={gettext("Voice identifier")}
                maxlength="120"
              />
            </div>
          </section>
        </.inputs_for>
      </.form>
      <section class="preferences-section" id="ai-account-allowance">
        <div class="preferences-section-heading">
          <.icon name="lucide-gauge" class="size-5" /><div>
            <h2>{gettext("Your AI allowance")}</h2><p>
              {gettext(
                "Daily credits reset at 00:00 UTC. Explanations cost 1, text generation 2, and illustrated generation 4 credits. Failed or canceled attempts count."
              )}
            </p>
          </div>
        </div>
        <p class="preferences-help" id="ai-shared-usage">
          {gettext("Application key")}: {@usage.used} / {@usage.limit}
        </p>
        <p class="preferences-help" id="ai-personal-usage">
          {gettext("Personal key")}: {@usage.personal_used} / {@usage.personal_limit}
        </p>
        <p class="preferences-help">
          {gettext(
            "Personal keys bypass the shared allowance, but still have a resource limit. Requests run one at a time per account."
          )}
        </p>
      </section>
      <section class="preferences-section" id="ai-provider-keys">
        <div class="preferences-section-heading">
          <.icon name="lucide-key-round" class="size-5" /><div>
            <h2>{gettext("Your provider keys")}</h2><p>
              {gettext(
                "Keys are encrypted on the server and used only for your account. Saved keys are never displayed again."
              )}
            </p>
          </div>
        </div>
        <ul class="credential-list" id="ai-credential-list" phx-update="stream">
          <li :for={{id, credential} <- @streams.credentials} id={id}>
            <span>{credential.provider} <small>•••• {credential.hint}</small></span>
            <button
              type="button"
              class="action"
              disabled={not Accounts.sudo_mode?(@current_scope.user)}
              phx-click="delete-key"
              phx-value-id={credential.id}
              data-confirm={gettext("Remove this saved provider key?")}
            >{gettext("Remove")}</button>
          </li>
        </ul>
        <p :if={not Accounts.sudo_mode?(@current_scope.user)} class="preferences-help">
          {gettext("Log in again before changing provider keys.")}
          <.link href={~p"/users/log-in"} class="text-link">{gettext("Log in")}</.link>
        </p>
        <.form
          :if={Accounts.sudo_mode?(@current_scope.user)}
          for={@credential_form}
          id="ai-credential-form"
          phx-submit="save-key"
        >
          <div class="preferences-fields">
            <.input
              id="ai-key-provider"
              field={@credential_form[:provider]}
              type="select"
              label={gettext("Provider")}
              options={Credential.providers()}
            />
            <.input
              id="ai-key-value"
              field={@credential_form[:api_key]}
              type="password"
              label={gettext("API key")}
              value=""
              autocomplete="off"
              maxlength="500"
              required
            />
          </div>
          <button type="submit" class="action" phx-disable-with={gettext("Saving…")}>{gettext(
            "Save provider key"
          )}</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save-key", %{"credential" => attrs}, socket) do
    if Accounts.sudo_mode?(socket.assigns.current_scope.user) do
      case AI.put_credential(socket.assigns.current_scope, attrs) do
        {:ok, _metadata} ->
          {:noreply,
           socket
           |> refresh_credentials()
           |> reset_credential_form()
           |> put_flash(:info, gettext("Provider key saved."))}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> reset_credential_form()
           |> put_flash(:error, gettext("Choose a provider and a valid key between 12 and 500 characters."))}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("Log in again before changing provider keys."))
       |> redirect(to: ~p"/users/log-in")}
    end
  end

  def handle_event("delete-key", %{"id" => id}, socket) do
    if Accounts.sudo_mode?(socket.assigns.current_scope.user) do
      {:ok, _} = AI.delete_credential(socket.assigns.current_scope, id)

      {:noreply,
       socket
       |> refresh_credentials()
       |> put_flash(:info, gettext("Provider key removed."))}
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("Log in again before changing provider keys."))
       |> redirect(to: ~p"/users/log-in")}
    end
  end

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

  defp refresh_credentials(socket) do
    credentials = AI.credentials(socket.assigns.current_scope)
    socket |> assign(credentials: credentials) |> stream(:credentials, credentials, reset: true)
  end

  defp reset_credential_form(socket) do
    socket |> assign(credential_form: blank_credential_form()) |> push_event("clear-provider-key", %{})
  end

  defp blank_credential_form, do: to_form(%{"provider" => "anthropic", "api_key" => ""}, as: "credential")

  defp available_models(credentials) do
    if Enum.any?(credentials, &(&1.provider == "anthropic")),
      do: Preferences.models(),
      else: Enum.filter(Preferences.models(), fn {_label, model} -> model in ["default", AI.shared_model()] end)
  end
end
