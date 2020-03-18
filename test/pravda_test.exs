defmodule PravdaTest do
  use ExUnit.Case
  doctest Pravda
  require Pravda.Loader

  import ExUnit.CaptureLog
  import Mock

  test "version returns a string" do
    assert is_binary(Pravda.version())
  end

  test "Compile path returns empty map" do
    result = Pravda.compile_paths([])
    assert(result == %{})
  end

  test "Compile paths returns map" do
    file = Pravda.Loader.read_file("test/petstore.json")
    result = Pravda.compile_paths([file])
    assert(result != %{})
    delete_endpoint = Map.get(result, {"DELETE", "/pet/{petId}"}) |> Map.get("1.0.0")
    keys = Map.keys(delete_endpoint)
    assert(:body in keys)
    assert(:params in keys)
    assert(:responses in keys)
    assert(:title in keys)
    assert(:random not in keys)
  end

  test "No paths returns empty map" do
    assert capture_log([level: :error], fn ->
             file = Pravda.Loader.read_file("test/no_paths.json")
             result = Pravda.compile_paths([file])
             assert(result == %{})
           end) =~ "No paths found"
  end

  test "No parms found returns empty list" do
    assert capture_log([level: :debug], fn ->
             file = Pravda.Loader.read_file("test/no_params.json")

             result =
               Pravda.compile_paths([file])
               |> Map.get({"POST", "/pet"})
               |> Map.get("1.0.0")
               |> Map.get(:params)

             assert(result == [])
           end) =~ "No parameters provided for post: /pet"
  end

  test "get responses returns empty map if none found" do
    file = Pravda.Loader.read_file("test/no_responses.json")

    responses =
      Pravda.compile_paths([file])
      |> Map.get({"DELETE", "/pet/{petId}"})
      |> Map.get("1.0.0")
      |> Map.get(:responses)

    assert(responses == %{})
  end

  test "phoenix_route_to_schema returns valid route" do
    with_mock Phoenix.Router,
      route_info: fn _router, _method, _route, _host ->
        %{
          log: :debug,
          path_params: %{"account_id" => "123456"},
          pipe_through: [:accept_json, :api],
          plug: Pravda,
          plug_opts: :no_thanks,
          route: "/good_route/:account_id"
        }
      end do
      assert(
        {"GET", "/good_route/{account_id}"} ==
          Pravda.phoenix_route_to_schema(
            %{method: "GET", request_path: "/good_route/123456", host: "localhost"},
            Pravda
          )
      )
    end
  end

  test "phoenix_route_to_schema returns no valid route" do
    with_mock Phoenix.Router,
      route_info: fn _router, _method, _route, _host ->
        :error
      end do
      assert(
        {nil, nil} ==
          Pravda.phoenix_route_to_schema(%{method: "GET", request_path: "/bad_route", host: "localhost"}, Pravda)
      )
    end
  end

  test "validate response is valid against a spec" do
    file = Pravda.Loader.read_file("test/petstore.json")

    responses =
      Pravda.compile_paths([file])
      |> Map.get({"GET", "/pet/findByStatus"})
      |> Map.get("1.0.0")

    assert(true == Pravda.validate_response(responses, "200", "[]"))
    assert(true == Pravda.validate_response(responses, "200", "[{\"name\":\"shirly\", \"photoUrls\":[]}]"))
  end

  test "invalidate response is valid against a spec" do
    file = Pravda.Loader.read_file("test/petstore.json")

    responses =
      Pravda.compile_paths([file])
      |> Map.get({"GET", "/pet/findByStatus"})
      |> Map.get("1.0.0")

    assert({false, _} = Pravda.validate_response(responses, "200", "{}"))
    assert({false, _} = Pravda.validate_response(responses, "666", "{}"))
    assert({false, _} = Pravda.validate_response(responses, "200", "[{\"names\":\"shirly\", \"photoUrls\":[]}]"))
    assert({false, _} = Pravda.validate_response(responses, "200", "[{\"names\":\"shirly\", \"photoUrls\":[]}]"))

    assert capture_log([level: :info], fn ->
             responses =
               Pravda.compile_paths([file])
               |> Map.get({"POST", "/pet"})
               |> Map.get("1.0.0")

             assert(true == Pravda.validate_response(responses, "405", "{}"))
           end) =~ "Spec is not complete enough for us to validate this, or response is not json and we cant validate"
  end

  test "broken json isnt attempted if we arent to read the body anyway" do
    file = Pravda.Loader.read_file("test/petstore.json")

    responses =
      Pravda.compile_paths([file])
      |> Map.get({"POST", "/pet"})
      |> Map.get("1.0.0")

    assert(true == Pravda.validate_response(responses, "405", "{ Not valid"))
  end

  test "Validate a body" do
    file = Pravda.Loader.read_file("test/petstore.json")

    path =
      Pravda.compile_paths([file])
      |> Map.get({"POST", "/pet"})
      |> Map.get("1.0.0")

    assert(true == Pravda.validate_body(path, %{"name" => "sally", "photoUrls" => []}))
  end

  test "Validate a body failed but was not required" do
    file = Pravda.Loader.read_file("test/petstore.json")

    path =
      Pravda.compile_paths([file])
      |> Map.get({"POST", "/store/order"})
      |> Map.get("1.0.0")

    assert capture_log([level: :debug], fn ->
             assert(true == Pravda.validate_body(path, %{"name" => "sally", "photoUrls" => [], "id" => "asdf"}))
           end) =~
             "Did not match schema but not required [{\"Type mismatch. Expected Integer but got String.\", \"#/id\"}]"
  end

  test "Validate a non body" do
    file = Pravda.Loader.read_file("test/petstore.json")

    path =
      Pravda.compile_paths([file])
      |> Map.get({"DELETE", "/pet/{petId}"})
      |> Map.get("1.0.0")

    assert capture_log([level: :debug], fn ->
             assert(true == Pravda.validate_body(path, %{}))
           end) =~ "Validated no body"
  end

  test "Validate an optional body not specced" do
    assert capture_log([level: :debug], fn ->
             assert(true == Pravda.validate_body(%{schema: %{}, body: %{body: false, required: false}}, "anything"))
           end) =~ "Validated optional body"
  end

  test "Validate params" do
    file = Pravda.Loader.read_file("test/petstore.json")

    path =
      Pravda.compile_paths([file])
      |> Map.get({"DELETE", "/pet/{petId}"})
      |> Map.get("1.0.0")

    assert(true == Pravda.validate_params(path, %{"api_key" => "5"}, %{"petId" => "7"}, %{"query_key" => "work"}))
  end

  test "Validate invalid params" do
    file = Pravda.Loader.read_file("test/petstore.json")

    path =
      Pravda.compile_paths([file])
      |> Map.get({"DELETE", "/pet/{petId}"})
      |> Map.get("1.0.0")

    {false, error} = Pravda.validate_params(path, %{"api_key" => 5}, %{}, %{})
    assert(is_list(Map.get(error, "reasons")))
  end

  test "Validate number params" do
    file = Pravda.Loader.read_file("test/petstore.json")

    path =
      Pravda.compile_paths([file])
      |> Map.get({"GET", "/pet/{petId}"})
      |> Map.get("1.0.0")

    assert(true == Pravda.validate_params(path, %{"api_key" => 5}, %{"petId" => "4"}, %{}))
    assert(true == Pravda.validate_params(path, %{"api_key" => 5}, %{"petId" => "4.4"}, %{}))
  end

  test "test bad paths for fix_path_params" do
    file = Pravda.Loader.read_file("test/petstore.json")

    path =
      Pravda.compile_paths([file])
      |> Map.get({"GET", "/pet/{petId}"})
      |> Map.get("1.0.0")

    {false, error} = Pravda.validate_params(path, %{"api_key" => 5}, %{"petId" => "asdf"}, %{})
    assert(is_list(Map.get(error, "reasons")))
    {false, error} = Pravda.validate_params(path, %{"api_key" => 5}, %{"petId" => "a.sdf"}, %{})
    assert(is_list(Map.get(error, "reasons")))

    path =
      Pravda.compile_paths([file])
      |> Map.get({"DELETE", "/pet/{petId}"})
      |> Map.get("1.0.0")

    {false, error} = Pravda.validate_params(path, %{"api_key" => 5}, %{"petId" => "a.sdf"}, %{})
    assert(is_list(Map.get(error, "reasons")))

    path =
      Pravda.compile_paths([file])
      |> Map.get({"POST", "/pet/{petId}"})
      |> Map.get("1.0.0")

    {false, error} = Pravda.validate_params(path, %{"api_key" => 5}, %{"petId" => "a.sdf"}, %{})
    assert(is_list(Map.get(error, "reasons")))
  end
end
