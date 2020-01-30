use Mix.Config

config :phoenix, :json_library, Jason
config :ex_json_schema,
  :remote_schema_resolver,
{Pravda.RemoteResolver, :resolve}
