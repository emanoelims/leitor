defmodule Mix.Tasks.Leitor.Ai.Configure do
  @shortdoc "Configures a development account's personal Claude credential and writing model"
  @moduledoc """
  Configures one existing development account without printing credentials.

      mix leitor.ai.configure --user-id UUID --use-application-key --writing-model anthropic:claude-opus-5-5

  This operator-only task deliberately copies the configured Anthropic key into
  that account's encrypted credential vault. Other accounts retain shared Haiku
  authorization. It is unavailable outside development; production users manage
  their own credentials through authenticated Preferences.
  """
  use Mix.Task

  alias Leitor.Accounts
  alias Leitor.Accounts.Scope
  alias Leitor.AI

  @doc "Imports the explicitly authorized application key into one development account and selects its writing model."
  @spec run([String.t()]) :: :ok
  @impl true
  def run(args) do
    if Mix.env() != :dev, do: Mix.raise("This task is available only in development")

    {opts, []} =
      OptionParser.parse!(args, strict: [user_id: :string, use_application_key: :boolean, writing_model: :string])

    if opts[:use_application_key] != true,
      do: Mix.raise("Pass --use-application-key to authorize this account's key import")

    user_id = Keyword.fetch!(opts, :user_id)
    model = Keyword.fetch!(opts, :writing_model)
    Mix.Task.run("app.start")
    user = Accounts.get_user!(user_id)
    scope = Scope.for_user(user)
    key = System.get_env("ANTHROPIC_API_KEY") || Mix.raise("ANTHROPIC_API_KEY is not configured")

    result =
      Leitor.Repo.transact(fn ->
        with {:ok, _} <- AI.put_credential(scope, %{provider: "anthropic", api_key: key}),
             {:ok, user} <- Accounts.update_preferences(scope, %{writing_model: model}) do
          {:ok, user.id}
        end
      end)

    case result do
      {:ok, _} -> Mix.shell().info("Development account configured. Provider key remains encrypted and undisplayed.")
      {:error, _} -> Mix.raise("Could not configure account; no changes were saved")
    end
  end
end
