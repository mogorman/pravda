use Mix.Config

config :ex_json_schema,
  :remote_schema_resolver,
{Pravda.RemoteResolver, :resolve}
