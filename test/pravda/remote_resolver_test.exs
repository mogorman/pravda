defmodule Pravda.RemoteResolverTest do
  use ExUnit.Case
  import Mock

  test "request a remote resource" do
    with_mocks([{Mojito, [:passthrough], [get: fn _url -> {:ok, %{body: "{}"}} end]}]) do
      assert is_map(Pravda.RemoteResolver.resolve("someurl"))
    end
  end
end
