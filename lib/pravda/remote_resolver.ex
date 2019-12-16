defmodule Pravda.RemoteResolver do
  def resolve(url) do
    {:ok, result} = Mojito.get(url)
    result.body |> Jason.decode!()
  end
end
