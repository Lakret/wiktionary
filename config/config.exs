# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

# Configures the endpoint
config :wiktionary, WiktionaryWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "lsH3cAaL8A01DKOJkp3z2RzNZGR39I48MH9MNNbzQQcZC4Ri7I65aBxNdEwo4qvf",
  render_errors: [view: WiktionaryWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Wiktionary.PubSub,
  live_view: [signing_salt: "E0J8yPUB"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
