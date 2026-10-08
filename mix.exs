defmodule Leitor.MixProject do
  use Mix.Project

  def project do
    [
      app: :leitor,
      version: "0.1.0",
      name: "Leitor",
      source_url: "https://github.com/emanoelims/leitor",
      docs: docs(),
      test_coverage: [
        summary: [threshold: 83],
        ignore_modules: [Leitor.DataCase, Leitor.AccountsFixtures, LeitorWeb.ConnCase]
      ],
      elixir: "~> 1.20.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      dialyzer: [
        plt_local_path: "_build/plts",
        plt_core_path: "_build/plts",
        plt_add_apps: [:ex_unit]
      ],
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Leitor.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, credo: :test, dialyzer: :test, doctor: :test, docs: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.4", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.9", only: [:dev]},
      {:argon2_elixir, "~> 4.0"},
      {:phoenix, "~> 1.8.15"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui", tag: "v5.7.47", sparse: "packages/bundle", app: false, compile: false, depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "main",
      formatters: ["html"],
      extras: ["README.md", "CONTRIBUTING.md", "CHANGELOG.md", "SECURITY.md", "guides/authentication-contracts.md"],
      groups_for_modules: [
        Accounts: [Leitor.Accounts, Leitor.Accounts.User, Leitor.Accounts.Scope],
        "Authentication internals": [Leitor.Accounts.UserToken, Leitor.Accounts.UserNotifier],
        "Web authentication": [LeitorWeb.UserAuth]
      ]
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind leitor", "esbuild leitor"],
      "assets.deploy": [
        "tailwind leitor --minify",
        "esbuild leitor --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "doctor --summary",
        "docs --warnings-as-errors",
        "dialyzer",
        "test"
      ]
    ]
  end
end
