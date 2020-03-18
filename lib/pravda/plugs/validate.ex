defmodule Pravda.Plugs.Validate do
  @moduledoc ~S"""
  Validates input and output according to an OpenAPI specs.

  Usage:

  Add the plug at the bottom of one or more pipelines in `router.ex`:

      pipeline "api" do
        # ...
        plug Pravada.Plugs.Validate, specs: [ "some_spec.json" ]
      end
  """
  require Logger
  import Plug.Conn
  alias Pravda.Helpers.Template

  @behaviour Plug

  @type path :: String.t()
  @type path_regex :: {path, Regex.t()}
  @type open_api_spec :: map()

  defp check(opts, key) do
    case Map.get(opts, key) do
      true ->
        true

      false ->
        false

      {app, key} ->
        Application.get_env(app, key)

      {app, key, default} ->
        Application.get_env(app, key, default)
    end
  end

  @impl Plug
  @doc ~S"""
  Init function sets all default variables and compiles the spec and paths so it can be fast. at run time.
  """
  def init(%{specs: raw_specs} = opts) do
    resolved_paths = Pravda.compile_paths(raw_specs)
    # set empty defaults for specs and paths just in case
    %{
      paths: resolved_paths,
      version: Map.get(opts, :version),
      disable: Map.get(opts, :disable, false),
      spec_var_placement: Map.get(opts, :spec_var_placement, :header),
      spec_var: Map.get(opts, :spec_var, nil),
      migration_callback: Map.get(opts, :migration_callback),
      all_paths_required: Map.get(opts, :all_paths_required, false),
      error_callback: Map.get(opts, :error_callback, nil),
      custom_error: Map.get(opts, :custom_error, nil),
      explain_error: Map.get(opts, :explain_error, true),
      validate_params: Map.get(opts, :validate_params, true),
      validate_body: Map.get(opts, :validate_body, true),
      validate_response: Map.get(opts, :validate_response, true),
      allow_invalid_input: Map.get(opts, :allow_invalid_input, false),
      allow_invalid_output: Map.get(opts, :allow_invalid_output, false),
      migrate_input: Map.get(opts, :migrate_input, true),
      migrate_output: Map.get(opts, :migrate_output, true)
    }
  end

  def init(_opts) do
    Logger.error("#{inspect(__MODULE__)}: specs are required but were not provided.")
    nil
  end

  @impl Plug
  @doc ~S"""
  Call function we attempt to validate params, then body, then our response body. and we return based on if we allow invalid input/output and the validity of the content
  """

  def call(conn, opts) do
    with false <- check(opts, :disable),
         {path, schema, matched_version} <- get_schema_url_from_request(conn, opts) do
      attempt_validate(path, schema, matched_version, conn, opts)
    else
      true ->
        conn

      nil ->
        case check(opts, :all_paths_required) do
          false ->
            Logger.info("No schema found for #{url(conn)}")
            conn

          _ ->
            Logger.error("No schema found for #{url(conn)}")
            error_handler(conn, opts, :not_found, {conn.method, conn.request_path, nil})
        end
    end
  end

  defp attempt_callback(_errors, _conn, %{error_callback: nil}) do
    nil
  end

  defp attempt_callback(errors, conn, %{error_callback: callback} = opts) when is_function(callback) do
    callback.(errors, conn, opts)
  end

  defp attempt_callback(errors, conn, %{error_callback: callback} = opts) do
    callback.error_callback(errors, conn, opts)
  end

  defp output_response(_errors, conn, _opts, true) do
    conn
  end

  defp output_response(errors, conn, opts, _) do
    error_handler(conn, opts, :invalid_response, {conn.method, conn.request_path, errors})
  end

  defp attempt_validate(path, schema, matched_version, conn, opts) do
    conn = conn |> Plug.Conn.fetch_query_params()

    with {:ok, version, conn} <-
           attempt_migrate_input(path, schema, matched_version, conn, opts, check(opts, :migrate_input)),
         true <- attempt_validate_params(schema, version, conn, opts, check(opts, :validate_params)),
         true <- attempt_validate_body(schema, version, conn, opts, check(opts, :validate_body)) do
      attempt_validate_response(
        conn,
        matched_version,
        opts,
        schema,
        path,
        check(opts, :validate_response) || check(opts, :migrate_output)
      )
    else
      error -> error
    end
  end

  @doc ~S"""
  attempt_validate_response checks to see if we are going to attempt to validate a response before we send it out.
  """
  @spec attempt_validate_response(Plug.Conn.t(), map(), map(), map(), tuple(), boolean()) :: Plug.Conn.t()
  def attempt_validate_response(conn, _matched_version, _opts, _schema, _path, false) do
    conn
  end

  def attempt_validate_response(conn, matched_version, opts, schema, path, _) do
    Plug.Conn.register_before_send(conn, fn conn ->
      opts =
        opts
        |> Map.put(:response_schema, schema)
        |> Map.put(:response_path, path)
        |> Map.put(:matched_version, matched_version)

      {conn, opts} = migrate_output(conn, opts, check(opts, :migrate_output))
      validate_response(conn, opts, check(opts, :validate_response))
    end)
  end

  defp migrate_output(conn, %{response_schema: schema} = opts, false) do
    {conn, Map.put(opts, :matched_version, List.last(schema["version"]))}
  end

  defp migrate_output(
         conn,
         %{response_path: path, response_schema: schema, matched_version: matched_version} = opts,
         true
       ) do
    conn =
      case Enum.at(schema["versions"], 0) == matched_version do
        true ->
          schema["versions"]

        false ->
          schema["versions"]
          |> Enum.chunk_by(&(&1 == matched_version))
          |> Enum.drop(1)
          |> List.flatten()
      end
      |> Enum.reverse()
      |> Enum.reduce(conn, fn schema_version, conn ->
        callback = Map.get(opts, :migration_callback)
        callback.down(path, schema_version, conn, opts)
        callback.down(:all, schema_version, conn, opts)
      end)

    {conn, opts}
  end

  defp validate_response(conn, _opts, false) do
    conn
  end

  defp validate_response(conn, %{response_schema: schema, matched_version: version} = opts, _) do
    case Pravda.validate_response(schema[version], conn.status, conn.resp_body) do
      true ->
        Logger.debug("Validated response for #{url(conn)}")
        conn

      {false, errors} ->
        Logger.error("Invalid response for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts)
        output_response(errors, conn, opts, check(opts, :allow_invalid_output))
    end
  end

  defp input_body(_errors, _conn, _opts, true) do
    true
  end

  defp input_body(errors, conn, opts, _) do
    error_handler(conn, opts, :invalid_body, {conn.method, conn.request_path, errors})
  end

  defp attempt_migrate_input(_path, _schema, version, conn, _opts, false) do
    {:ok, version, conn}
  end

  defp attempt_migrate_input(path, schema, matched_version, conn, opts, true) do
    supported_versions = schema["versions"]

    conn =
      supported_versions
      |> Enum.chunk_by(&(&1 == matched_version))
      |> Enum.drop(1)
      |> List.flatten()
      |> Enum.reduce(conn, fn schema_version, conn ->
        callback = Map.get(opts, :migration_callback)
        callback.up(path, schema_version, conn, opts)
        callback.up(:all, schema_version, conn, opts)
      end)

    last_version = List.last(supported_versions)
    spec_var = Map.get(opts, :spec_var, nil)

    case Map.get(opts, :spec_var_placement) do
      :header ->
        {:ok, last_version, put_req_header(conn, spec_var, last_version)}

      :query ->
        {:ok, last_version,
         %Plug.Conn{
           conn
           | params: Map.put(conn.params, spec_var, last_version),
             query_params: Map.put(conn.query_params, spec_var, last_version)
         }}

      :path ->
        {:ok, last_version,
         %Plug.Conn{
           conn
           | params: Map.put(conn.params, spec_var, last_version),
             path_params: Map.put(conn.path_params, spec_var, last_version)
         }}
    end
  end

  defp attempt_validate_body(_schema, _version, _conn, _opts, false) do
    true
  end

  defp attempt_validate_body(schema, version, conn, opts, _) do
    case Pravda.validate_body(schema[version], conn.body_params) do
      true ->
        Logger.debug("Validated body for #{url(conn)}")
        true

      {false, errors} ->
        Logger.error("Invalid body for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts)
        input_body(errors, conn, opts, check(opts, :allow_invalid_input))
    end
  end

  defp input_params(_errors, _conn, _opts, true) do
    true
  end

  defp input_params(errors, conn, opts, _) do
    error_handler(conn, opts, :invalid_params, {conn.method, conn.request_path, errors})
  end

  defp attempt_validate_params(_schema, _version, _conn, _opts, false) do
    true
  end

  defp attempt_validate_params(schema, version, conn, opts, _) do
    headers = conn.req_headers |> Map.new()

    case Pravda.validate_params(schema[version], headers, conn.path_params, conn.query_params) do
      true ->
        Logger.debug("Validated prams for #{url(conn)}")
        true

      {false, errors} ->
        Logger.error("Invalid params for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts)
        input_params(errors, conn, opts, check(opts, :allow_invalid_input))
    end
  end

  defp error_handler(conn, opts, error, info) do
    case Map.get(opts, :custom_error) do
      nil ->
        standard_error_handler(conn, opts, error, info)

      custom ->
        custom.error_handler(conn, opts, error, info)
    end
  end

  defp standard_error_handler(conn, opts, error, info) do
    message =
      case check(opts, :explain_error) do
        true ->
          Jason.encode!(Template.get_stock_message(error, info))

        false ->
          ""
      end

    conn
    |> put_resp_header("content-type", "application/json")
    |> resp(Template.get_stock_code(error), message)
    |> halt()
  end

  defp url(conn) do
    "#{conn.method}:#{conn.request_path}"
  end

  def closest_input_version(versions, match_version) do
    Enum.reduce(versions, Enum.at(versions, 0), fn version, acc ->
      case Version.compare(version, match_version) do
        :lt ->
          version

        :eq ->
          version

        :gt ->
          acc
      end
    end)
  end

  defp get_closest_input_schema_with_version(schema, nil) do
    Map.get(schema, "versions") |> List.first()
  end

  defp get_closest_input_schema_with_version(schema, version) do
    case Map.get(schema, version) do
      nil ->
        versions = Map.get(schema, "versions")
        closest_version = closest_input_version(versions, version)
        get_closest_input_schema_with_version(schema, closest_version)

      _result ->
        version
    end
  end

  defp get_initial_schema_with_version(conn, %{spec_var: var_name, spec_var_placement: :header}) do
    case Plug.Conn.get_req_header(conn, var_name) do
      [version] ->
        version

      _ ->
        nil
    end
  end

  defp get_initial_schema_with_version(conn, %{spec_var: var_name, spec_var_placement: :body}) do
    Map.get(conn.body_params, var_name)
  end

  defp get_initial_schema_with_version(conn, %{spec_var: var_name, spec_var_placement: :query}) do
    Map.get(conn.query_params, var_name)
  end

  defp get_initial_schema_with_version(conn, %{spec_var: var_name, spec_var_placement: :path}) do
    Map.get(conn.path_params, var_name)
  end

  defp get_initial_schema_with_version(_conn, _opts) do
    nil
  end

  defp get_schema_url_from_request(conn, opts) do
    router = (Map.get(conn, :private) || %{}) |> Map.get(:phoenix_router)

    case router do
      nil ->
        nil

      _ ->
        path = Pravda.phoenix_route_to_schema(conn, router)
        case Map.fetch(opts.paths, path) do
	  {:ok, schema} ->
            input_version = get_initial_schema_with_version(conn, opts)
            matched_version = get_closest_input_schema_with_version(schema, input_version)
	    {path, schema, matched_version}
	  _->
	    nil
	end
    end
  end
end
