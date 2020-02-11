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
      disable: Map.get(opts, :disable, false),
      all_paths_required: Map.get(opts, :all_paths_required, false),
      error_callback: Map.get(opts, :error_callback, nil),
      custom_error: Map.get(opts, :custom_error, nil),
      explain_error: Map.get(opts, :explain_error, true),
      validate_params: Map.get(opts, :validate_params, true),
      validate_body: Map.get(opts, :validate_body, true),
      validate_response: Map.get(opts, :validate_response, true),
      allow_invalid_input: Map.get(opts, :allow_invalid_input, false),
      allow_invalid_output: Map.get(opts, :allow_invalid_output, false),
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
         schema when not is_nil(schema) <- get_schema_url_from_request(conn, opts) do
      attempt_validate(schema, conn, opts)
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

  defp attempt_validate(schema, conn, opts) do
    with true <- attempt_validate_params(schema, conn, opts, check(opts, :validate_params)),
         true <- attempt_validate_body(schema, conn, opts, check(opts, :validate_body)) do
      attempt_validate_response(conn, opts, schema, check(opts, :validate_response))
    else
      error -> error
    end
  end

  @doc ~S"""
  attempt_validate_response checks to see if we are going to attempt to validate a response before we send it out.
  """
  @spec attempt_validate_response(Plug.Conn.t(), map(), map(), boolean()) :: Plug.Conn.t()
  def attempt_validate_response(conn, _opts, _schema, false) do
    conn
  end

  def attempt_validate_response(conn, opts, schema, _) do
    Plug.Conn.register_before_send(conn, fn conn ->
      validate_response(conn, Map.put(opts, :response_schema, schema))
    end)
  end

  defp validate_response(conn, %{response_schema: schema} = opts) do
    case Pravda.validate_response(schema, conn.status, conn.resp_body) do
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

  defp attempt_validate_body(_schema, _conn, _opts, false) do
    true
  end

  defp attempt_validate_body(schema, conn, opts, _) do
    case Pravda.validate_body(schema, conn.body_params) do
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

  defp attempt_validate_params(_schema, _conn, _opts, false) do
    true
  end

  defp attempt_validate_params(schema, conn, opts, _) do
    conn = conn |> Plug.Conn.fetch_query_params()
    headers = conn.req_headers |> Map.new()

    case Pravda.validate_params(schema, headers, conn.path_params, conn.query_params) do
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

  defp get_schema_url_from_request(conn, opts) do
    router = (Map.get(conn, :private) || %{}) |> Map.get(:phoenix_router)

    case router do
      nil ->
        nil

      _ ->
        key = Pravda.phoenix_route_to_schema(conn, router)
        Map.get(opts.paths, key)
    end
  end
end
