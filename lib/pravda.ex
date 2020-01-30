defmodule Pravda do
  require Logger

  @moduledoc """
  Documentation for Pravda.
  """

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

  @doc ~S"""
  Returns the version of the currently loaded Pravda, in string format.
  """
  #  @spec compile_specs(module(), list()) :: map()
  def compile_paths(router, raw_specs) do
    Enum.map(raw_specs, fn raw_spec -> compile_spec(router, raw_spec) end)
    |> List.flatten()
    |> Map.new()
  end

  @spec compile_spec(module(), any()) :: map()
  def compile_spec(router, raw_spec) do
    spec = Pravda.Loader.load(raw_spec)
    add_schema(router, spec)
  end

  def add_schema(router, spec) do
    case ExJsonSchema.Schema.get_fragment(spec, [
           :root,
           "paths",
         ]) do
      {:error, _} ->
        Logger.error("No paths found")

      {:ok, paths} ->
        title = get_title(spec)

        Enum.map(List.flatten(build_routes(paths)), fn path -> is_routable(router, path, title, spec) end)
        |> Enum.reject(fn item -> is_nil(item) end)
    end
  end

  defp is_routable(_router, {method, path}, title, schema) do
    lower_method = String.downcase(method)

    {{method, path},
     %{
       params: get_params(lower_method, path, schema),
       body: get_body(lower_method, path, schema),
       responses: get_responses(lower_method, path, schema),
       title: title,
       schema: schema,
     }}
  end

  # Phoenix.Router.route_info does not seem available at compile time look more into this later
  # case Phoenix.Router.route_info(router, method, path, "") do
  #       :error ->
  #         Logger.warn("No implementation found for route [#{title}] #{method}: #{path}")
  #         nil
  #       route ->
  #         schema_url =
  #           Enum.reduce(route.path_params, route.route, fn {param, _value},
  #                                                          path ->
  #             String.replace(path, ":#{param}", "{#{param}}")
  #           end)
  #         case schema_url == path do
  #           true ->

  #             {{method, path}, %{params: get_params(lower_method, path, schema),
  #                              body: get_body(lower_method, path, schema),
  #                              responses: get_responses(lower_method, path, schema),
  #                              title: title,
  # #                             schema: schema
  #                             }}
  #           false ->
  #             Logger.error("No Match for route [#{title}] #{method}: #{path} != #{schema_url}")
  #             nil
  #         end
  #     end

  defp build_route(route_name, methods) do
    Enum.map(
      methods,
      fn method ->
        method = String.upcase(method)
        {method, route_name}
      end
    )
  end

  defp build_routes(api_routes) do
    #    router = Module.concat(app, Router)

    Enum.map(
      api_routes,
      fn {route_name, route} ->
        build_route(route_name, Map.keys(route))
      end
    )
  end

  defp get_title(schema) do
    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "info",
         ]) do
      {:error, _} ->
        false

      {:ok, result} ->
        Map.get(result, "title")
    end
  end

  defp get_params(method, path, schema) do
    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "paths",
           path,
           method,
           "parameters",
         ]) do
      {:error, _} ->
        Logger.warn("No parameters provided for #{method}: #{path}")
        []

      {:ok, params} ->
        Enum.map(params, fn param ->
          deref_if_possible(param, schema)
        end)
    end
  end

  defp get_body(method, path, schema) do
    required =
      case ExJsonSchema.Schema.get_fragment(schema, [
             :root,
             "paths",
             path,
             method,
             "requestBody",
             "required",
           ]) do
        {:error, _} ->
          true

        {:ok, result} ->
          result
      end

    body =
      case ExJsonSchema.Schema.get_fragment(schema, [
             :root,
             "paths",
             path,
             method,
             "requestBody",
             "content",
             "application/json",
             "schema",
           ]) do
        {:error, _} ->
          false

        {:ok, result} ->
          deref_if_possible(result, schema)
      end

    %{required: required, body: body}
  end

  defp get_response(response_code, method, path, schema) do
    string_response_code = "#{response_code}"

    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "paths",
           path,
           method,
           "responses",
           string_response_code,
           "content",
           "application/json",
           "schema",
         ]) do
      {:error, _} ->
        {string_response_code, false}

      {:ok, result} ->
        {string_response_code, deref_if_possible(result, schema)}
    end
  end

  defp get_responses(method, path, schema) do
    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "paths",
           path,
           method,
           "responses",
         ]) do
      {:error, _} ->
        %{}

      {:ok, responses} ->
        Enum.map(responses, fn {response_code, _object} ->
          get_response(response_code, method, path, schema)
        end)
        |> Map.new()
    end
  end

  defp deref_if_possible(false, _schema) do
    false
  end

  defp deref_if_possible(result, schema) do
    case Map.get(result, "$ref") do
      nil ->
        result

      ref ->
        ExJsonSchema.Schema.get_fragment!(schema, ref)
    end
  end

  def phoenix_route_to_schema(conn, router) do
    case Phoenix.Router.route_info(router, conn.method, conn.request_path, conn.host) do
      :error ->
        Logger.warn("No implementation found for route #{conn.method}: #{conn.request_path}")
        {nil, nil}

      route ->
        schema_url =
          Enum.reduce(route.path_params, route.route, fn {param, _value}, path ->
            String.replace(path, ":#{param}", "{#{param}}")
          end)

        {conn.method, schema_url}
    end
  end

  def validate_response(schema, conn) do
    responses = schema.responses

    body =
      case Jason.decode(conn.resp_body) do
        {:ok, json} -> json
        _ -> %{"error" => "invalid json"}
      end

    case Map.get(responses, "#{conn.status}") do
      nil ->
        {false, %{"body" => body, "errors" => "response for status code, #{conn.status}, not found in spec"}}

      response ->
        fragment_schema = deref_if_possible(response, schema.schema)

        case ExJsonSchema.Validator.validate_fragment(
               schema.schema,
               fragment_schema,
               body
             ) do
          :ok ->
            true

          {:error, reason} ->
            {false, %{"body" => body, "errors" => reason |> Map.new()}}
        end
    end
  end

  defp validate_body_fragment(schema, fragment, body) do
    case ExJsonSchema.Validator.validate_fragment(schema, fragment, body) do
      :ok ->
        Logger.debug("Validated body")
        true

      {:error, reasons} ->
        case required do
          true ->
            {false, %{reason: reasons |> Map.new()}}

          _ ->
            Logger.debug("Did not match schema but not required #{inspect(reasons)}")
            true
        end
    end
  end

  def validate_body(schema, conn) do
    body = schema.body

    fragment =
      Map.get(body, :body)
      |> deref_if_possible(schema.schema)

    required = Map.get(body, :required, true)

    case {fragment, conn.body_params, required} do
      # no body, no body provided, dont care if required
      {false, %{}, _} ->
        Logger.debug("Validated no body")
        true

      # no body, anything provided, not required
      {false, _, false} ->
        Logger.debug("Validated optional body")
        true

      # no body, something provided, required to be empty
      {false, _, true} ->
        false
        {false, %{reason: "Body was provided when  not allowed"}}

      # normal fragment
      _ ->
        validate_body_fragment(schema.schema, fragment, conn.body_params)
    end
  end

  defp validate_param(param, schema, headers, conn) do
    name = Map.get(param, "name")

    fragment_schema =
      Map.get(param, "schema")
      |> deref_if_possible(schema.schema)

    required = Map.get(param, "required", true)

    input_data =
      case Map.get(param, "in") do
        "path" ->
          Map.get(conn.path_params, name)
          |> fix_path_params(fragment_schema)

        "query" ->
          Map.get(conn.query_params, name)

        "header" ->
          Map.get(headers, name)
      end

    case ExJsonSchema.Validator.validate_fragment(
           schema.schema,
           fragment_schema,
           input_data
         ) do
      :ok ->
        true

      {:error, reason} ->
        case is_nil(input_data) and required == false do
          true ->
            true

          false ->
            %{name: name, reason: reason |> Map.new()}
        end
    end
  end

  def validate_params(schema, conn) do
    params = schema.params
    headers = conn.req_headers |> Map.new()

    Enum.map(params, fn param ->
      validate_param(param, schema, headers, conn)
    end)
    |> Enum.reject(fn param -> param == true end)
    |> (fn failed_params ->
          case failed_params do
            [] ->
              Logger.debug("Validated Params")
              true

            _ ->
              {false, failed_params}
          end
        end).()
  end

  defp fix_path_params(param, %{"type" => "integer"}) do
    case Integer.parse(param) do
      {int, ""} ->
        int

      _ ->
        param
    end
  end

  defp fix_path_params(param, %{"type" => "number"}) do
    case param =~ "." do
      true ->
        case Float.parse(param) do
          {float, ""} ->
            float

          _ ->
            param
        end

      false ->
        case Integer.parse(param) do
          {int, ""} ->
            int

          _ ->
            param
        end
    end
  end

  defp fix_path_params("true", %{"type" => "boolean"}), do: true
  defp fix_path_params("false", %{"type" => "boolean"}), do: false
  defp fix_path_params("null", %{"type" => "null"}), do: nil

  defp fix_path_params(param, _) do
    param
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
