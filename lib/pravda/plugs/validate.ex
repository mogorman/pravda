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
  def init(%{router: router, specs: raw_specs} = opts) do
    resolved_paths = Pravda.compile_paths(router, raw_specs)
    # set empty defaults for specs and paths just in case
    %{
      paths: resolved_paths,
      all_paths_required: Map.get(opts, :all_paths_required, false),
      custom_error: Map.get(opts, :custom_error, nil),
      explain_error: Map.get(opts, :explain_error, true),
      validate_params: Map.get(opts, :validate_params, true),
      validate_body: Map.get(opts, :validate_body, true),
      validate_response: Map.get(opts, :validate_response, true),
      output_stubs: Map.get(opts, :output_stubs, false),
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

  defp attempt_validate(schema, conn, opts) do
    case attempt_validate_params(schema, conn, opts) do
      {false, errors} ->
        error_handler(conn, opts, :invalid_params, {conn.method, conn.request_path, errors})

      {true, _} ->
        case attempt_validate_body(schema, conn, opts) do
          {false, errors} ->
            error_handler(conn, opts, :invalid_body, {conn.method, conn.request_path, errors})

          {true, _} ->
            case Map.get(opts, :validate_response) do
              true ->
                Plug.Conn.register_before_send(conn, fn conn ->
                  attempt_validate_response(conn, Map.put(opts, :pravda, schema))
                end)

              false ->
                conn
            end
        end
    end
  end

  def attempt_validate_response(conn, opts) do
    schema = opts.pravda

    case Pravda.validate_response(schema, conn) do
      true ->
        Logger.debug("Validated Response")
        conn

      {false, errors} ->
        case opts.allow_invalid_output do
          true ->
            Logger.error("Server is responding with invalid data #{inspect(errors)}")
            conn

          false ->
            error_handler(conn, opts, :invalid_response, {conn.method, conn.request_path, errors})
        end
    end
  end

  defp attempt_validate_body(schema, conn, opts) do
    case opts.validate_body do
      false ->
        {true, nil}

      _ ->
        case Pravda.validate_body(schema, conn) do
          true ->
            {true, nil}

          {false, errors} ->
            Logger.error("Invalid body for #{url(conn)} #{inspect(errors)}")
            {opts.allow_invalid_input, errors}
        end
    end
  end

  defp attempt_validate_params(schema, conn, opts) do
    conn = conn |> Plug.Conn.fetch_query_params()

    case opts.validate_params do
      false ->
        {true, nil}

      _ ->
        case Pravda.validate_params(schema, conn) do
          true ->
            {true, nil}

          {false, errors} ->
            Logger.error("Invalid params for #{url(conn)} #{inspect(errors)}")
            {opts.allow_invalid_input, errors}
        end
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
