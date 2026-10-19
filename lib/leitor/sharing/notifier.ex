defmodule Leitor.Sharing.Notifier do
  @moduledoc "Delivers explicitly requested page invitations through the configured application mailer."
  import Swoosh.Email

  @doc "Sends an invitation link, not an authentication token; restricted access still requires the invited confirmed email."
  @spec invite(String.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def invite(email, title, url) do
    new()
    |> to(email)
    |> from(Application.fetch_env!(:leitor, :mail_from))
    |> subject("A page was shared with you")
    |> text_body(
      "You have been invited to read #{title}.\n\n#{url}\n\nIf access is restricted, sign in with this email address to open the page."
    )
    |> Leitor.Mailer.deliver()
  end
end
