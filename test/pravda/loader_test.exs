defmodule Pravda.LoaderTest do
  use ExUnit.Case
  require Pravda.Loader

  test "Test file is loaded at compile time" do
    result = Pravda.Loader.read_file("test/petstore.json")
    assert(is_binary(result))
  end

  test "Test file is converted to json correctly" do
    result =
      Pravda.Loader.read_file("test/petstore.json")
      |> Pravda.Loader.load()

    assert(is_map(result))
  end
end
