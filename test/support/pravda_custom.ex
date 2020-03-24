defmodule PravdaTest.PravdaCustom do
  import Plug.Conn
  alias Pravda.Helpers.Template

  @moduledoc ~S"""
  dummy module to validate custom callback
  """

  def error_handler(conn, _opts, error, _info) do
    status = Template.get_stock_code(error)

    conn
    |> put_status(status)
  end
end
