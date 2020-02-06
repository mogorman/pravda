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

  @impl Plug
  def init(%{specs: raw_specs} = opts) do
    resolved_paths = Pravda.compile_paths(raw_specs)
    # set empty defaults for specs and paths just in case
    %{
      paths: resolved_paths,
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
    Logger.error("#{inspect(__MODULE__)}: specs and a router are required but were not provided.")

    nil
  end

  @impl Plug
  def call(conn, opts) do
    case get_schema_url_from_request(conn, opts) do
      nil ->
        case Map.get(opts, :all_paths_required) do
          false ->
            Logger.info("No schema found for #{url(conn)}")
            conn

          _ ->
            Logger.error("No schema found for #{url(conn)}")
            error_handler(conn, opts, :not_found, {conn.method, conn.request_path, nil})
        end

      schema ->
        attempt_validate(schema, conn, opts)
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

  defp output_response(_errors, conn, %{allow_invalid_output: true}) do
    conn
  end

  defp output_response(errors, conn, opts) do
    error_handler(conn, opts, :invalid_response, {conn.method, conn.request_path, errors})
  end

  defp attempt_validate(schema, conn, opts) do
    with true <- attempt_validate_params(schema, conn, opts),
         true <- attempt_validate_body(schema, conn, opts) do
      attempt_validate_response(conn, opts, schema)
    else
      error -> error
    end
  end

  def attempt_validate_response(conn, %{validate_response: false}) do
    conn
  end

  def attempt_validate_response(conn, opts, schema) do
    Plug.Conn.register_before_send(conn, fn conn ->
      validate_response(conn, Map.put(opts, :response_schema, schema))
    end)
  end

  def validate_response(conn, %{response_schema: schema} = opts) do
    case Pravda.validate_response(schema, conn.status, conn.resp_body) do
      true ->
        Logger.debug("Validated response for #{url(conn)}")
        conn

      {false, errors} ->
        Logger.error("Invalid response for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts)
        output_response(errors, conn, opts)
    end
  end

  defp input_body(_errors, _conn, %{allow_invalid_output: true}) do
    true
  end

  defp input_body(errors, conn, opts) do
    error_handler(conn, opts, :invalid_body, {conn.method, conn.request_path, errors})
  end

  defp attempt_validate_body(_schema, _conn, %{validate_body: false}) do
    true
  end

  defp attempt_validate_body(schema, conn, opts) do
    case Pravda.validate_body(schema, conn.body_params) do
      true ->
        Logger.debug("Validated body for #{url(conn)}")
        true

      {false, errors} ->
        Logger.error("Invalid body for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts)
        input_body(errors, conn, opts)
    end
  end

  defp input_params(_errors, _conn, %{allow_invalid_output: true}) do
    true
  end

  defp input_params(errors, conn, opts) do
    error_handler(conn, opts, :invalid_params, {conn.method, conn.request_path, errors})
  end

  defp attempt_validate_params(_schema, _conn, %{validate_params: false}) do
    true
  end

  defp attempt_validate_params(schema, conn, opts) do
    conn = conn |> Plug.Conn.fetch_query_params()
    headers = conn.req_headers |> Map.new()

    case Pravda.validate_params(schema, headers, conn.path_params, conn.query_params) do
      true ->
        Logger.debug("Validated prams for #{url(conn)}")
        true

      {false, errors} ->
        Logger.error("Invalid params for #{url(conn)} #{inspect(errors)}")
        attempt_callback(errors, conn, opts)
        input_params(errors, conn, opts)
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
      case Map.get(opts, :explain_error) do
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
