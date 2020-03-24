defmodule PravdaTest.PravdaCustom do
  import Plug.Conn

  def error_handler(conn, _opts, error, _info) do
    status = Pravda.Helpers.Template.get_stock_code(error)

    conn
    |> put_status(status)
  end
end
