defmodule Leitor.Repo do
  use Ecto.Repo,
    otp_app: :leitor,
    adapter: Ecto.Adapters.Postgres
end
