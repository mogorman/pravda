defmodule Pravda.ConfigTest do
  use ExUnit.Case

  test "test options" do
    assert(Pravda.Config.config(:spec_var_placement, []) == :header)
    assert(Pravda.Config.config(:spec_var_placement, spec_var_placement: :body) == :body)
  end

  test "test compressor levels" do
  end
end
