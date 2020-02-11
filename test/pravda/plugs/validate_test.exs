defmodule Pravda.Plugs.ValidateTest do
  use ExUnit.Case
  doctest Pravda.Plugs.Validate
  require Pravda.Loader

  import ExUnit.CaptureLog
  import Mock

  alias Pravda.Plugs.Validate

  test "validate init with no args returns nil" do
    assert capture_log([level: :error], fn ->
             assert is_nil(Validate.init([]))
           end) =~ "specs are required but were not provided."
  end

  test "validate init" do
    assert(is_map(Validate.init(%{specs: [Pravda.Loader.read_file("test/petstore.json")]})))
  end
end
