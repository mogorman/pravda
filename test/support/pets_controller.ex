defmodule PravdaTest.PetsController do
  use Phoenix.Controller

  def index(conn, %{"name" => "FAIL"} = _params) do
    json(conn, %{"pravda_pet" => 7})
  end

  def index(conn, _params) do
    json(conn, %{"pravda_pet" => "asdf"})
  end
end
