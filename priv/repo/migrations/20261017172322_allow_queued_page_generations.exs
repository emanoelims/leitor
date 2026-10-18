defmodule Leitor.Repo.Migrations.AllowQueuedPageGenerations do
  use Ecto.Migration

  def up do
    drop constraint(:page_generations, :page_generation_status)

    create constraint(:page_generations, :page_generation_status,
             check: "status IN ('queued', 'running', 'ready', 'failed')"
           )
  end

  def down do
    execute "UPDATE page_generations SET status = 'failed', error = 'figure_budget_exceeded' WHERE status = 'queued'"
    drop constraint(:page_generations, :page_generation_status)

    create constraint(:page_generations, :page_generation_status,
             check: "status IN ('running', 'ready', 'failed')"
           )
  end
end
