defmodule Pravda.LoaderTest do
  use ExUnit.Case

  require Pravda.Loader

  test "can read a file" do
    file = Pravda.Loader.read_file("test/test_file")
    assert(is_binary(file))
    assert(file == "hello world")
  end

  test "can read a directory" do
    files = Pravda.Loader.read_dir("test/")
    Enum.map(files, fn file -> assert(is_binary(file)) end)
    assert(Enum.any?(files, fn file -> file == "hello world" end))
  end

  test "can load a file" do
    file = Pravda.Loader.read_file("test/petstore.json")
    schema = Pravda.Loader.load(file)

    version =
      Map.get(schema, :schema, %{})
      |> Map.get("openapi")

    assert(version == "3.0.0")
  end

  test "can load a json blob" do
    json_blob =
      Pravda.Loader.read_file("test/petstore.json")
      |> Jason.decode!()

    schema = Pravda.Loader.load(json_blob)

    version =
      Map.get(schema, :schema, %{})
      |> Map.get("openapi")

    assert(version == "3.0.0")
  end

  test "fails gracefully if load fails" do
    schema = Pravda.Loader.load(nil)
    assert(schema == %{})
  end
end
