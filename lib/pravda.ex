defmodule Pravda do
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
  alias Pravda.{Core, Config}

  @behaviour Plug

  @type path :: String.t()
  @type path_regex :: {path, Regex.t()}
  @type open_api_spec :: map()

  @impl Plug
  @doc ~S"""
  Init function sets all default variables and compiles the spec and paths so it can be fast. at run time.
  """

  # Convert map to keyword list if they gave us the wrong data type.
  def init(opts) when is_map(opts) do
    Enum.map(opts, fn {key, value} -> {key, value} end)
    |> init()
  end

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts) do
    compiled_specs = Core.compile_paths(Config.config(:specs, opts)) || %{}
    name = Config.config(:name, opts)

    opts
    |> Keyword.update(:specs, compiled_specs, fn _ -> compiled_specs end)
    |> Keyword.update(:name, name, fn _ -> name end)
  end

  @impl Plug
  @doc ~S"""
  Call function we attempt to validate params, then body, then our response body. and we return based on if we allow invalid input/output and the validity of the content
  """
  @spec call(Conn.t(), Keyword.t()) :: Conn.t()
  def call(conn, opts) do
    with true <- Config.config(:enable, opts),
         conn <- Plug.Conn.fetch_query_params(conn),
         {path, matched_version} <- get_schema_url_from_request(conn, opts) do
      attempt_validate(path, matched_version, conn, opts)
    else
      false ->
        conn

      nil ->
        case Config.config(:all_paths_required, opts) do
          false ->
            Logger.info("No schema found for #{url(conn)}")
            conn

          _ ->
            Logger.error("No schema found for #{url(conn)}")
            error_handler(conn, opts, :not_found, {conn.method, conn.request_path, nil})
        end
    end
  end

  defp attempt_callback(_errors, _conn, _opts, nil) do
    nil
  end

  defp attempt_callback(errors, conn, opts, callback) when is_function(callback) do
    callback.(errors, conn, opts)
  end

  defp attempt_callback(errors, conn, opts, callback) do
    callback.error_callback(errors, conn, opts)
  end

  defp output_response(_errors, conn, _opts, true) do
    conn
  end

  defp output_response(errors, conn, opts, _) do
    error_handler(conn, opts, :invalid_response, {conn.method, conn.request_path, errors})
  end

  defp attempt_validate(path, matched_version, conn, opts) do
    conn = conn |> Plug.Conn.fetch_query_params()

    with {:ok, version, conn} <-
           attempt_migrate_input(path, matched_version, conn, opts, Config.config(:migrate_input, opts)),
         true <- attempt_validate_params(path, version, conn, opts, Config.config(:validate_params, opts)),
         true <- attempt_validate_body(path, version, conn, opts, Config.config(:validate_body, opts)) do
      attempt_validate_response(
        conn,
        opts,
        matched_version,
        path,
        Config.config(:validate_response, opts) || Config.config(:migrate_output, opts)
      )
    else
      error -> error
    end
  end

  @doc ~S"""
  attempt_validate_response checks to see if we are going to attempt to validate a response before we send it out.
  """
  @spec attempt_validate_response(Plug.Conn.t(), map(), String.t(), {String.t(), String.t()}, boolean()) ::
          Plug.Conn.t()
  def attempt_validate_response(conn, _opts, _matched_version, _path, false) do
    conn
  end

  def attempt_validate_response(conn, opts, matched_version, path, _) do
    Plug.Conn.register_before_send(conn, fn conn ->
      opts =
        opts
        |> Keyword.put(:response_path, path)
        |> Keyword.put(:matched_version, matched_version)

      resp_body = get_json_resp_body(conn.resp_body)

      {conn, opts, resp_body} = migrate_output(conn, opts, resp_body, Config.config(:migrate_output, opts))
      validate_response(conn, opts, resp_body, Config.config(:validate_response, opts))
    end)
  end

  defp get_json_resp_body(resp_body) do
    with true <- String.valid?(IO.iodata_to_binary(resp_body)),
         {:ok, body} <- Jason.decode(resp_body) do
      {:ok, body}
    else
      false ->
        {:error, "not a string"}

      _ ->
        {:error, resp_body}
    end
  end

  defp migrate_output(conn, opts, resp_body, false) do
    specs = Config.config(:specs, opts)
    opts = Keyword.put(opts, :matched_version, List.last(specs["versions"]))
    {conn, opts, resp_body}
  end

  defp migrate_output(conn, opts, resp_body, true) do
    path = Keyword.get(opts, :response_path)
    matched_version = Keyword.get(opts, :matched_version)
    specs = Config.config(:specs, opts)
    callback = Config.config(:migration_callback, opts)

    {conn, resp_body} =
      case Enum.find_index(specs["versions"], fn version -> version == matched_version end) do
        nil ->
          []

        index ->
          Enum.slice(specs["versions"], (index + 1)..-1)
      end
      |> Enum.reverse()
      |> Enum.reduce({conn, resp_body}, fn spec_version, {conn, resp_body} ->
        {conn, resp_body} = callback.down(path, conn.status, spec_version, conn, opts, resp_body)
        callback.down(:all, conn.status, spec_version, conn, opts, resp_body)
      end)

    {conn, opts, resp_body}
  end

  defp validate_response(conn, _opts, _resp_body, false) do
    conn
  end

  defp validate_response(conn, opts, resp_body, _) do
    path = Keyword.get(opts, :response_path)
    matched_version = Keyword.get(opts, :matched_version)
    specs = Config.config(:specs, opts)

    case Core.validate_response(path, specs[matched_version], conn.status, resp_body) do
      true ->
        Logger.debug("Validated response for #{url(conn)}")
        conn

      {false, errors} ->
        Logger.error("Invalid response for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts, Config.config(:error_callback, opts))
        output_response(errors, conn, opts, Config.config(:allow_invalid_output, opts))
    end
  end

  defp input_body(_errors, _conn, _opts, true) do
    true
  end

  defp input_body(errors, conn, opts, _) do
    error_handler(conn, opts, :invalid_body, {conn.method, conn.request_path, errors})
  end

  defp attempt_migrate_input(_path, version, conn, _opts, false) do
    {:ok, version, conn}
  end

  defp attempt_migrate_input(path, matched_version, conn, opts, true) do
    specs = Config.config(:specs, opts)
    supported_versions = specs["versions"]
    callback = Config.config(:migration_callback, opts)

    conn =
      case Enum.find_index(supported_versions, &(&1 == matched_version)) do
        nil ->
          []

        index ->
          Enum.slice(supported_versions, (index + 1)..-1)
      end
      |> Enum.reduce(conn, fn schema_version, conn ->
        callback.up(path, schema_version, conn, opts)
        callback.up(:all, schema_version, conn, opts)
      end)

    last_version = List.last(supported_versions)
    spec_var = Config.config(:spec_var, opts)
    spec_var_placement = Config.config(:spec_var_placement, opts)

    case {spec_var, spec_var_placement} do
      {nil, _} ->
        {:ok, last_version, conn}

      {spec_var, :header} ->
        {:ok, last_version, put_req_header(conn, spec_var, last_version)}

      {spec_var, :query} ->
        {:ok, last_version,
         %Plug.Conn{
           conn
           | params: Map.put(conn.params, spec_var, last_version),
             query_params: Map.put(conn.query_params, spec_var, last_version)
         }}

      {spec_var, :path} ->
        {:ok, last_version,
         %Plug.Conn{
           conn
           | params: Map.put(conn.params, spec_var, last_version),
             path_params: Map.put(conn.path_params, spec_var, last_version)
         }}

      _ ->
        {:ok, last_version, conn}
    end
  end

  defp attempt_validate_body(_path, _version, _conn, _opts, false) do
    true
  end

  defp attempt_validate_body(path, version, conn, opts, _) do
    spec = Config.config(:specs, opts) |> Map.get(version)

    case Core.validate_body(path, spec, conn.body_params) do
      true ->
        Logger.debug("Validated body for #{url(conn)}")
        true

      {false, errors} ->
        Logger.error("Invalid body for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts, Config.config(:error_callback, opts))
        input_body(errors, conn, opts, Config.config(:allow_invalid_input, opts))
    end
  end

  defp input_params(_errors, _conn, _opts, true) do
    true
  end

  defp input_params(errors, conn, opts, _) do
    error_handler(conn, opts, :invalid_params, {conn.method, conn.request_path, errors})
  end

  defp attempt_validate_params(_path, _version, _conn, _opts, false) do
    true
  end

  defp attempt_validate_params(path, version, conn, opts, _) do
    spec = Config.config(:specs, opts) |> Map.get(version)
    headers = conn.req_headers |> Map.new()

    case Core.validate_params(path, spec, headers, conn.path_params, conn.query_params) do
      true ->
        Logger.debug("Validated prams for #{url(conn)}")
        true

      {false, errors} ->
        Logger.error("Invalid params for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts, Config.config(:error_callback, opts))
        input_params(errors, conn, opts, Config.config(:allow_invalid_input, opts))
    end
  end

  defp error_handler(conn, opts, error, info) do
    case Config.config(:custom_error_callback, opts) do
      nil ->
        standard_error_handler(conn, opts, error, info)

      custom ->
        custom.error_handler(conn, opts, error, info)
    end
  end

  defp standard_error_handler(conn, opts, error, info) do
    message =
      case Config.config(:explain_error, opts) do
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

  def get_closest_input_schema_with_version(_version, nil) do
    nil
  end

  def get_closest_input_schema_with_version(nil, versions) do
    List.first(versions)
  end

  def get_closest_input_schema_with_version(version, versions) do
    case Enum.any?(versions, &(&1 == version)) do
      true ->
        version

      false ->
        closest_input_version(versions, version)
    end
  end

  defp get_initial_schema_with_version(_conn, nil, _) do
    nil
  end

  defp get_initial_schema_with_version(conn, var_name, :header) do
    case Plug.Conn.get_req_header(conn, var_name) do
      [version] ->
        version

      _ ->
        nil
    end
  end

  defp get_initial_schema_with_version(conn, var_name, :body) do
    Map.get(conn.body_params, var_name)
  end

  defp get_initial_schema_with_version(conn, var_name, :query) do
    Map.get(conn.query_params, var_name)
  end

  defp get_initial_schema_with_version(conn, var_name, :path) do
    Map.get(conn.path_params, var_name)
  end

  defp get_initial_schema_with_version(_conn, _var_name, _placement) do
    nil
  end

  defp get_schema_url_from_request(conn, opts) do
    with router when not is_nil(router) <- (Map.get(conn, :private) || %{}) |> Map.get(:phoenix_router),
         spec_var <- Config.config(:spec_var, opts),
         placement <- Config.config(:spec_var_placement, opts),
         specs <- Config.config(:specs, opts),
         version <- get_initial_schema_with_version(conn, spec_var, placement),
         version when not is_nil(version) <- get_closest_input_schema_with_version(version, Map.get(specs, "versions")) do
      {method, path} = Core.phoenix_route_to_schema(conn, router)

      path_exists =
        specs[version].schema
        |> Map.get("paths", %{})
        |> Map.get(path, %{})
        |> Map.get(String.downcase(method))

      case path_exists do
        nil ->
          nil

        _ ->
          {{String.downcase(method), path}, version}
      end
    else
      _ -> nil
    end
  end

  @doc ~S"""
  Returns the version of the currently loaded Pravda, in string format.
  """
  @spec version() :: String.t()
  def version do
    Application.loaded_applications()
    |> Enum.map(fn {app, _, ver} -> if app == :pravda, do: ver, else: nil end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
    |> to_string
  end
end
