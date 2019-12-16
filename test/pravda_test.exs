defmodule PravdaTest do
  use ExUnit.Case
  doctest Pravda

  test "version returns a string" do
    assert is_binary(Pravda.version())
  end
end
