defmodule Mix.Tasks.Leitor.Ai.Finish do
  @shortdoc "Releases an owned development AI lease after its worker has stopped"
  @moduledoc """
  Releases an abandoned development lease without refunding attempted credits.

      mix leitor.ai.finish --user-id UUID --lease-id UUID

  Stop the matching local worker first. This task does not stop remote provider
  work or execute user code. Normal generations finish their own leases; this
  operator recovery path is for interrupted local development commands only.
  """
  use Mix.Task

  alias Leitor.Accounts
  alias Leitor.Accounts.Scope
  alias Leitor.AI

  @doc "Releases the named account's lease idempotently in development."
  @spec run([String.t()]) :: :ok
  @impl true
  def run(args) do
    if Mix.env() != :dev, do: Mix.raise("This task is available only in development")
    {options, []} = OptionParser.parse!(args, strict: [user_id: :string, lease_id: :string])
    Mix.Task.run("app.start")
    scope = options |> Keyword.fetch!(:user_id) |> Accounts.get_user!() |> Scope.for_user()
    :ok = AI.finish(scope, Keyword.fetch!(options, :lease_id))
    Mix.shell().info("Development lease released; attempted credits remain charged.")
  end
end
