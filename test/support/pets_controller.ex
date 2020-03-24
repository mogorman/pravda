defmodule PravdaTest.PetsController do
  use Phoenix.Controller

  def index(conn, _params) do
    json(conn, %{"pet" => "asdf"})
  end
end
