defmodule Pravda do
  @moduledoc """
  Documentation for Pravda.
  """

  @doc ~S"""
  Returns the version of the currently loaded Pravda, in string format.
  """
  def version do
    Application.loaded_applications()
    |> Enum.map(fn {app, _, ver} -> if app == :pravda, do: ver, else: nil end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
    |> to_string
  end
end
