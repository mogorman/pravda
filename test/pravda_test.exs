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
    delete_endpoint = Map.get(result, {"DELETE", "/pet/{petId}"})
    keys = Map.keys(delete_endpoint)
    assert(:body in keys)
    assert(:params in keys)
    assert(:responses in keys)
    assert(:schema in keys)
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

  test "get responses returns empty map if none found" do
    file = Pravda.Loader.read_file("test/no_responses.json")
    responses = Pravda.compile_paths([file])
    |> Map.get({"DELETE", "/pet/{petId}"})
    |> Map.get(:responses)
    assert(responses == %{})
  end
end
