defmodule Pravda.RemoteResolver do
  @moduledoc """
  Remote Resolver is used by ex_json_schema to presolve remote refs over http
  """

  @doc ~S"""
  resolve json schema.
  """
  @spec resolve(String.t()) :: map()
  def resolve(url) do
    {:ok, result} = Mojito.get(url)
    result.body |> Jason.decode!()
  end
end
