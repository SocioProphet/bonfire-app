# In this file, we load production configuration and secrets
# from environment variables. You can also hardcode secrets,
# although such is generally not recommended and you have to
# remember to add this file to your .gitignore.
import Config

host = System.get_env("HOSTNAME", "localhost")
server_port = String.to_integer(System.get_env("SERVER_PORT", "4000"))
public_port = String.to_integer(System.get_env("PUBLIC_PORT", "4000"))

repos =
  if System.get_env("TEST_INSTANCE") == "yes",
    do: [Bonfire.Common.Repo, Bonfire.Common.TestInstanceRepo],
    else: [Bonfire.Common.Repo]

# [Bonfire.Common.Repo, Beacon.Repo]

if (config_env() == :prod or System.get_env("OTEL_ENABLED") == "1") and
     (System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") || System.get_env("OTEL_LIGHTSEP_API_KEY") ||
        System.get_env("OTEL_HONEYCOMB_API_KEY")) do
  config :opentelemetry,
    disabled: false

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf

  otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")

  if otel_endpoint do
    IO.puts("NOTE: OTLP (open telemetry) data will be sent to #{otel_endpoint}")

    config :opentelemetry_exporter,
      otlp_endpoint: otel_endpoint
  end

  if System.get_env("OTEL_LIGHTSEP_API_KEY") do
    IO.puts("NOTE: OTLP (open telemetry) data will be sent to lightstep.com")
    # Example configuration for Lightstep.com, for more refers to:
    # https://github.com/open-telemetry/opentelemetry-erlang/tree/main/apps/opentelemetry_exporter#application-environment
    config :opentelemetry_exporter,
      # You can configure the compression type for exporting traces.
      otlp_compression: :gzip,
      oltp_traces_compression: :gzip,
      otlp_traces_endpoint: "https://ingest.lightstep.com:443/traces/otlp/v0.9",
      otlp_headers: [
        {"lightstep-access-token", System.get_env("OTEL_LIGHTSEP_API_KEY")}
      ]
  end

  if System.get_env("OTEL_HONEYCOMB_API_KEY") do
    IO.puts("NOTE: OTLP (open telemetry) data will be sent to honeycomb.io")

    config :opentelemetry, :processors,
      otel_batch_processor: %{
        exporter: {
          :opentelemetry_exporter,
          %{
            endpoints: [
              {:https, 'api.honeycomb.io', 443,
               [
                 verify: :verify_peer,
                 cacertfile: :certifi.cacertfile(),
                 depth: 3,
                 customize_hostname_check: [
                   match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
                 ]
               ]}
            ],
            headers: [
              {"x-honeycomb-team", System.fetch_env!("OTEL_HONEYCOMB_API_KEY")},
              {"x-honeycomb-dataset", System.get_env("OTEL_SERVICE_NAME", "bonfire")}
            ],
            protocol: :grpc
          }
        }
      }
  end
end

## load extensions' runtime configs (and behaviours) directly via extension-provided modules
Bonfire.Common.Config.LoadExtensionsConfig.load_configs(Bonfire.RuntimeConfig)
##

System.get_env("DATABASE_URL") || System.get_env("POSTGRES_PASSWORD") || System.get_env("CI") ||
  raise """
  Environment variables for database are missing.
  For example: DATABASE_URL=ecto://USER:PASS@HOST/DATABASE
  You can also set POSTGRES_PASSWORD (required),
  and POSTGRES_USER (default: postgres) and POSTGRES_HOST (default: localhost)
  """

repo_connection_config =
  if System.get_env("DATABASE_URL") do
    [url: System.get_env("DATABASE_URL")]
  else
    [
      username: System.get_env("POSTGRES_USER", "postgres"),
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      hostname: System.get_env("POSTGRES_HOST", "localhost")
    ]
  end

secret_key_base =
  System.get_env("SECRET_KEY_BASE") || System.get_env("CI") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

signing_salt =
  System.get_env("SIGNING_SALT") || System.get_env("CI") ||
    raise """
    environment variable SIGNING_SALT is missing.
    """

encryption_salt =
  System.get_env("ENCRYPTION_SALT") || System.get_env("CI") ||
    raise """
    environment variable ENCRYPTION_SALT is missing.
    """

config :bonfire,
  host: host,
  app_name: System.get_env("APP_NAME", "Bonfire"),
  ap_base_path: System.get_env("AP_BASE_PATH", "/pub"),
  github_token: System.get_env("GITHUB_TOKEN"),
  show_debug_errors_in_dev: System.get_env("SHOW_DEBUG_IN_DEV"),
  encryption_salt: encryption_salt,
  signing_salt: signing_salt,
  root_path: File.cwd!()

config :bonfire, Bonfire.Web.Endpoint,
  server:
    config_env() != :test or System.get_env("TEST_INSTANCE") == "yes" or
      System.get_env("START_SERVER") == "yes",
  url: [
    host: host,
    port: public_port
  ],
  http: [
    port: server_port,
    transport_options:
      if(System.get_env("PLUG_SERVER") != "bandit",
        do: [max_connections: 16_384, socket_opts: [:inet6]],
        else: [:inet6]
      )
  ],
  adapter:
    if(System.get_env("PLUG_SERVER") != "bandit",
      do: Phoenix.Endpoint.Cowboy2Adapter,
      else: Bandit.PhoenixAdapter
    ),
  secret_key_base: secret_key_base,
  live_view: [signing_salt: signing_salt]

if System.get_env("SENTRY_DSN") do
  IO.puts("NOTE: errors will be reported to Sentry.")

  config :sentry,
    dsn: System.get_env("SENTRY_DSN")

  if System.get_env("SENTRY_NAME") do
    config :sentry, server_name: System.get_env("SENTRY_NAME")
  end
else
  config :sentry,
    disabled: true
end

pool_size = String.to_integer(System.get_env("POOL_SIZE", "10"))

database =
  case config_env() do
    :test -> "bonfire_test#{System.get_env("MIX_TEST_PARTITION")}"
    :dev -> System.get_env("POSTGRES_DB", "bonfire_dev")
    _ -> System.get_env("POSTGRES_DB", "bonfire")
  end

config :bonfire, ecto_repos: repos
config :bonfire_umbrella, ecto_repos: repos
config :paginator, ecto_repos: repos
config :activity_pub, ecto_repos: repos
config :bonfire, Bonfire.Common.Repo, repo_connection_config
config :bonfire, Bonfire.Common.TestInstanceRepo, repo_connection_config
config :beacon, Beacon.Repo, repo_connection_config
config :bonfire, Bonfire.Common.Repo, database: database
config :beacon, Beacon.Repo, database: database
config :paginator, Paginator.Repo, database: database
config :beacon, Beacon.Repo, pool_size: pool_size
config :bonfire, Bonfire.Common.TestInstanceRepo, priv: "priv/repo"

config :activity_pub, Oban,
  repo: Bonfire.Common.Repo,
  queues: false

# start prod-only config
if config_env() == :prod do
  config :bonfire, Bonfire.Common.Repo,
    # ssl: true,
    # database: System.get_env("POSTGRES_DB", "bonfire"),
    pool_size: pool_size,
    # Note: keep this disabled if using ecto_dev_logger or EctoSparkles.Log instead #
    log: String.to_atom(System.get_env("DB_QUERIES_LOG_LEVEL", "false"))
end

# prod only config

# start prod and dev only config
if config_env() != :test do
  config :bonfire, Bonfire.Common.Repo,
    slow_query_ms: String.to_integer(System.get_env("SLOW_QUERY_MS", "100"))
end

## bonfire_livebook
if Code.ensure_loaded?(Livebook) do
  Livebook.config_runtime()
end

IO.puts("Welcome to Bonfire!")
