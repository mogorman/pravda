defmodule Pravda do
  require Logger

  @moduledoc """
  Documentation for Pravda.
  """

  @doc ~S"""
  Compile Paths is the function used to take a list of spec files and compile them into a
  list of routes we can validate with.
  """
  @spec compile_paths(list()) :: map()
  def compile_paths(raw_specs) do
    Enum.map(raw_specs, fn raw_spec -> compile_spec(raw_spec) end)
    |> List.flatten()
    |> Map.new()
  end

  defp compile_spec(raw_spec) do
    spec = Pravda.Loader.load(raw_spec)
    add_schema(spec)
  end

  defp add_schema(spec) do
    case ExJsonSchema.Schema.get_fragment(spec, [
           :root,
           "paths",
         ]) do
      {:error, _} ->
        Logger.error("No paths found")
        []

      {:ok, paths} ->
        title = get_title(spec)

        Enum.map(List.flatten(build_routes(paths)), fn path -> is_routable(path, title, spec) end)
        |> Enum.reject(fn item -> is_nil(item) end)
    end
  end

  defp is_routable({method, path}, title, schema) do
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
        Logger.debug("No parameters provided for #{method}: #{path}")
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

  @doc ~S"""
  phoenix_route_to_schema takes a connections current path location and method
  and outputs a url that will match an openapi schema base definition it uses
  the router to correctly resolve the name and order of path arguments
  """
  @spec phoenix_route_to_schema(Plug.Conn.t(), module()) :: {String.t(), String.t()} | {nil, nil}
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

  defp reasons_to_list(reasons) do
    Enum.map(reasons, fn {error, ref} ->
      %{"error" => error, "ref" => ref}
    end)
  end

  @doc ~S"""
  validate_response is used to validate the responses section for a spec, for a specific method, path, and status.
  """
  @spec validate_response(map(), String.t() | integer(), String.t()) :: true | {false, map()}
  def validate_response(schema, status, resp_body) do
    with response when not is_nil(response) <- Map.get(schema.responses, "#{status}"),
         fragment_schema when fragment_schema != false <- deref_if_possible(response, schema.schema),
         {:ok, body} <- Jason.decode(resp_body) do
      case ExJsonSchema.Validator.validate_fragment(
             schema.schema,
             fragment_schema,
             body
           ) do
        :ok ->
          true

        {:error, reasons} ->
          {false, %{"body" => body, "reasons" => reasons_to_list(reasons)}}
      end
    else
      nil ->
        {false,
         %{
           "body" => resp_body,
           "reasons" => reasons_to_list([{"response for status code, #{status}, not found in spec", ""}]),
         }}

      false ->
        Logger.info("Spec is not complete enough for us to validate this, or response is not json and we cant validate")
        true

      _ ->
        {false, %{"body" => resp_body, "reasons" => reasons_to_list([{"Invalid Json not able to decode", ""}])}}
    end
  end

  defp validate_body_fragment(schema, fragment, body, required) do
    case ExJsonSchema.Validator.validate_fragment(schema, fragment, body) do
      :ok ->
        Logger.debug("Validated body")
        true

      {:error, reasons} ->
        case required do
          false ->
            Logger.debug("Did not match schema but not required #{inspect(reasons)}")
            true

          _ ->
            {false, %{"body" => body, "reasons" => reasons_to_list(reasons)}}
        end
    end
  end

  @doc ~S"""
  validate_body is used to validate the input body for a spec, for a specific method, path.
  """
  @spec validate_body(map(), map()) :: true | {false, map()}
  def validate_body(schema, body_params) do
    body = schema.body

    fragment =
      Map.get(body, :body)
      |> deref_if_possible(schema.schema)

    required = Map.get(body, :required, true)

    case {fragment, body_params, required} do
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
        {false, %{"body" => body_params, "reasons" => reasons_to_list([{"Body was provided when not allowed", ""}])}}

      # normal fragment
      _ ->
        validate_body_fragment(schema.schema, fragment, body_params, required)
    end
  end

  defp validate_param(param, schema, headers, path_params, query_params) do
    name = Map.get(param, "name")

    fragment_schema =
      Map.get(param, "schema")
      |> deref_if_possible(schema.schema)

    required = Map.get(param, "required", true)
    type = Map.get(param, "in")

    input_data =
      case type do
        "path" ->
          Map.get(path_params, name)
          |> fix_path_params(fragment_schema)

        "query" ->
          Map.get(query_params, name)

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

      {:error, reasons} ->
        case is_nil(input_data) and required == false do
          true ->
            true

          false ->
            Enum.map(reasons, fn {error, ref} ->
              %{"input" => input_data, "name" => name, "type" => type, "error" => error, "ref" => ref}
            end)
        end
    end
  end

  @doc ~S"""
  validate params takes in and validates headers, path, and query parameters against the spec
  """
  @spec validate_params(map(), map(), map(), map()) :: true | {false, map()}
  def validate_params(schema, headers, path_params, query_params) do
    params = schema.params

    Enum.map(params, fn param ->
      validate_param(param, schema, headers, path_params, query_params)
    end)
    |> Enum.reject(fn param -> param == true end)
    |> (fn failed_params ->
          case failed_params do
            [] ->
              Logger.debug("Validated Params")
              true

            _ ->
              {false, %{"reasons" => List.flatten(failed_params)}}
          end
        end).()
  end

  defp fix_path_params(nil, %{"type" => "integer"}) do
    nil
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
