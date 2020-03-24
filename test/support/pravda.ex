defmodule PravdaTest.Pravda do
  @spec error_callback(map(), Plug.Conn.t(), map()) :: any()
  def error_callback(errors, conn, _opts) do
    nil
  end
end
