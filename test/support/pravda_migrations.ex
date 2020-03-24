defmodule PravdaTest.PravdaMigrations do
  alias Plug.Conn
  # UP
  def up(:all, "2.0.0", conn, _opts) do
    conn
    |> Conn.put_req_header("new-header", "itworks")
  end

  # CATCHALL FOR UP
  def up(_path, _version, conn, _opts) do
    conn
  end

  # DOWN
  def down({"post", "/pravda/pets"}, 200, "2.0.0", conn, _opts, {:ok, json_body}) do
    json = Map.put(json_body, "old_key", true)
    conn = Map.put(conn, :resp_body, Jason.encode!(json))
    {conn, {:ok, json}}
  end

  # CATCHALL FOR DOWN
  def down(_path, _status, _version, conn, _opts, json_tuple) do
    {conn, json_tuple}
  end
end
