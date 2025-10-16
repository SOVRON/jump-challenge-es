defmodule Jump.MixProject do
  use Mix.Project

  def project do
    [
      app: :jump,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
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
      mod: {Jump.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
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
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:igniter, "~> 0.5", only: :dev},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Auth (Google sign-in + generic OAuth2)
      {:ueberauth, "~> 0.10"},
      # Google strategy (scopes for Gmail/Calendar)
      {:ueberauth_google, "~> 0.12"},
      # HubSpot strategy (scopes for Contacts/CRM)
      {:ueberauth_hubspot, "~> 0.1.0"},
      # token exchange/refresh (generic)
      {:oauth2, "~> 2.1"},

      # Google APIs (official auto-generated clients)
      # https://hexdocs.pm/google_api_calendar/api-reference.html
      {:google_api_gmail, "~> 0.17"},
      # https://hexdocs.pm/google_api_gmail/api-reference.html
      {:google_api_calendar, "~> 0.26"},

      # HTTP clients (for HubSpot REST + any fallbacks)
      {:req, "~> 0.5"},
      {:tesla, "~> 1.15"},

      # Background jobs / scheduling / persistence
      # jobs, retries, cron-like scheduling
      {:oban, "~> 2.20"},

      # Push pipelines for Pub/Sub (optional, if you choose push over polling)
      {:broadway, "~> 1.2"},
      {:broadway_cloud_pub_sub, "~> 0.9"},

      # Vector search + DB
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      # Ecto type + distance functions
      {:pgvector, "~> 0.3"},

      # LLM usage (chat, tool-calling, embeddings)
      {:openai_ex, "~> 0.9.18"},
      {:langchain, "~> 0.4.0"},

      # Email compose/parse helpers
      # to build MIME (send via Gmail API)
      {:swoosh, "~> 1.16"},
      # optional: low-level RFC 2822 compose
      {:mail, "~> 0.4"},
      # MIME types
      {:mime, "~> 2.0"},

      # HTML parsing/cleanup for RAG chunking
      {:floki, "~> 0.38"},

      # Timezones & formatting (meeting proposals, etc.)
      {:timex, "~> 3.7"},

      # JSON / validation
      {:jason, "~> 1.4"},
      # optional: validate tool-call outputs
      {:ex_json_schema, "~> 0.11"}
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
      test: ["test --exclude db"],
      "test.all": ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind jump", "esbuild jump"],
      "assets.deploy": [
        "tailwind jump --minify",
        "esbuild jump --minify",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
