defmodule PravdaTest.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(Pravda)
  end

  scope "/pravda", PravdaTest do
    pipe_through(:api)
    get("/pets", PetsController, :index)
  end
end
