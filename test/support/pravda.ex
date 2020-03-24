defmodule PravdaTest.Pravda do
  @moduledoc """
  A dummy file to test user error callbacks  
  """

  @spec error_callback(map(), Plug.Conn.t(), map()) :: any()
  def error_callback(_errors, _conn, _opts) do
    nil
  end
end
