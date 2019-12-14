defmodule PravdaTest do
  use ExUnit.Case
  doctest Pravda

  test "greets the world" do
    assert Pravda.hello() == :world
  end
end
