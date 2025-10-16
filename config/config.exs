# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :jump,
  ecto_repos: [Jump.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure Ecto to use Pgvector extension for vector types
config :jump, Jump.Repo, types: Jump.PostgrexTypes

# Configures the endpoint
config :jump, JumpWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: JumpWeb.ErrorHTML, json: JumpWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Jump.PubSub,
  live_view: [signing_salt: "GKpsgl4I"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :jump, Jump.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  jump: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  jump: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Oban background job system
config :jump, Oban,
  repo: Jump.Repo,
  queues: [
    default: 50,
    ingest: 20,
    embed: 30,
    outbound: 20,
    sync: 10,
    webhooks: 10
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Refresh expiring Google tokens every hour
       {"0 * * * *", Jump.Workers.CronTokenRefresh},
       # Gmail history sync every 5 minutes (dispatcher enqueues per-user jobs)
       {"*/5 * * * *", Jump.Workers.CronGmailSync},
       # Calendar sync every 10 minutes (dispatcher enqueues per-user jobs)
       {"*/10 * * * *", Jump.Workers.CronCalendarSync},
       # HubSpot contact sync every 30 minutes (dispatcher enqueues per-user jobs)
       {"*/30 * * * *", Jump.Workers.CronHubspotSync},
       # Calendar watch renewal every 6 hours (dispatcher enqueues per-user jobs)
       {"0 */6 * * *", Jump.Workers.CronCalendarWatchRenewal}
     ]}
  ]

# Tesla global configuration
config :tesla, disable_deprecated_builder_warning: true

# Ueberauth configuration for OAuth providers
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope:
           "email profile https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/calendar",
         access_type: "offline",
         prompt: "consent"
       ]},
    hubspot:
      {Ueberauth.Strategy.Hubspot,
       [
         default_scope:
           "oauth crm.objects.contacts.read crm.objects.contacts.write crm.schemas.contacts.read",
         scope:
           "oauth crm.objects.contacts.read crm.objects.contacts.write crm.schemas.contacts.read",
         access_type: "offline"
       ]}
  ]

# HubSpot API configuration
config :ueberauth_hubspot, :base_api_url, "https://api.hubapi.com"

# OpenAIEx and LangChain configurations moved to runtime.exs for proper runtime loading

# Gmail API configuration
config :jump, Jump.Gmail.Client,
  rate_limit_delay_ms: 100,
  max_retries: 3,
  messages_per_page: 50

# RAG configuration
config :jump, Jump.RAG,
  default_chunk_size: 800,
  default_overlap: 125,
  embedding_model: "text-embedding-3-small",
  embedding_dimensions: 1536,
  max_search_results: 15

# Calendar API configuration
config :jump, Jump.Calendar.Client,
  rate_limit_delay_ms: 200,
  max_retries: 3,
  events_per_page: 250

# Calendar configuration
config :jump, Jump.Calendar,
  default_timezone: "UTC",
  default_business_hours: %{start: "09:00", end: "17:00"},
  default_meeting_duration: 30,
  default_buffer_minutes: 15,
  # 7 days
  webhook_ttl_seconds: 604_800,
  # 1 day before expiration
  renewal_threshold_seconds: 86_400

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
