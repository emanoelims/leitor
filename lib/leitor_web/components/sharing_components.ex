defmodule LeitorWeb.SharingComponents do
  @moduledoc false
  use LeitorWeb, :html

  attr :share, :any, required: true
  attr :share_url, :string, required: true
  attr :members, :any, required: true
  attr :invite_form, :any, required: true
  attr :sharing_form, :any, required: true

  def panel(assigns) do
    ~H"""
    <StudyComponents.dialog
      id="page-sharing-dialog"
      title={gettext("Share page")}
      on_close={JS.push("share-page")}
    >
      <p class="muted">
        {gettext("Share this page. Your personal notebook and AI conversations stay private.")}
      </p>
      <.form
        for={@invite_form}
        id="page-invite-form"
        phx-submit="invite-collaborator"
        class="sharing-invite"
      >
        <.input
          field={@invite_form[:email]}
          type="email"
          label={gettext("Invite by email")}
          placeholder={gettext("Email address")}
          required
          maxlength="160"
        />
        <.input
          field={@invite_form[:role]}
          type="select"
          label={gettext("Permission")}
          options={[{gettext("Can view"), "view"}, {gettext("Can comment"), "comment"}]}
        />
        <button class="action action-primary" type="submit" phx-disable-with={gettext("Sending…")}>{gettext(
          "Invite"
        )}</button>
      </.form>
      <div id="page-collaborators" phx-update="stream" class="sharing-members">
        <p id="page-collaborators-empty" class="hidden only:block muted">
          {gettext("Only you have explicit access.")}
        </p>
        <div :for={{dom_id, member} <- @members} id={dom_id} class="sharing-member">
          <span>{member.email}</span>
          <.form
            for={to_form(%{"role" => member.role}, as: "collaborator")}
            id={"permission-#{member.id}"}
            phx-change="collaborator-role"
            phx-value-id={member.id}
          >
            <.input
              type="select"
              name="collaborator[role]"
              value={member.role}
              aria-label={gettext("Permission for %{email}", email: member.email)}
              options={[{gettext("Can view"), "view"}, {gettext("Can comment"), "comment"}]}
            />
          </.form>
          <button
            type="button"
            class="icon-button"
            phx-click="remove-collaborator"
            phx-value-id={member.id}
            aria-label={gettext("Remove access for %{email}", email: member.email)}
          ><.icon name="lucide-x" class="size-4" /></button>
        </div>
      </div>
      <.form for={@sharing_form} id="page-link-access" phx-change="set-link-access">
        <.input
          field={@sharing_form[:link_role]}
          type="select"
          label={gettext("General access")}
          options={[
            {gettext("Restricted · only invited people"), "disabled"},
            {gettext("Anyone with the link can view"), "view"},
            {gettext("Anyone with the link can comment"), "comment"}
          ]}
        />
      </.form>
      <p class="sharing-help muted">
        {gettext(
          "Link access applies even after an individual invitation is removed. Visitors with comment access can join using a display name."
        )}
      </p>
      <div class="sharing-link-row">
        <button
          type="button"
          id="copy-share-link"
          class="action action-primary"
          phx-click={
            JS.dispatch("leitor:copy", detail: %{text: @share_url, status_id: "share-copy-status"})
          }
        ><.icon name="lucide-copy" class="size-4" />{gettext("Copy link")}</button>
        <.link id="open-shared-page" navigate={~p"/s/#{@share.token}"} class="action">{gettext(
          "Open shared page"
        )}</.link>
        <button type="button" id="renew-share-link" class="action" phx-click="renew-share-link">{gettext(
          "Renew link"
        )}</button>
      </div>
      <p id="share-copy-status" phx-update="ignore" role="status" class="muted"></p>
    </StudyComponents.dialog>
    """
  end
end
