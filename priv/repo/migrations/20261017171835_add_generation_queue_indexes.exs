defmodule Leitor.Repo.Migrations.AddGenerationQueueIndexes do
  use Ecto.Migration

  def change do
    create unique_index(:page_generations, [:user_id],
             where: "status = 'queued'",
             name: :one_waiting_generation_per_account
           )

    create index(:page_generations, [:status, :id])
  end
end
