defmodule Pravda.Loader do
  require Logger

  @moduledoc """
  This loads the spec into a compiled binary. It is useful as the specs might not be available in the priv folder or on the deployed machine. this way we build up the spec file at compile time and not at run time.
  """

  @doc """
  Read_file exposes the macro that allows you to point to any local file and have it be part of the deploy on release.
  """
  defmacro read_file(file_name) do
    File.read!(file_name)
  end

  defmacro read_dir(dir_name) do
    recursive_read(dir_name)
  end

  def recursive_read(dir) do
    Enum.map(File.ls!(dir), fn file ->
      file_name = "#{dir}/#{file}"

      case File.dir?(file_name) do
        true ->
          recursive_read(file_name)

        false ->
          File.read!(file_name)
      end
    end)
    |> List.flatten()
  end

  @spec load(any()) :: ExJsonSchema.Schema.Root.t() | map()
  def load(json) when is_map(json) do
    ExJsonSchema.Schema.resolve(json)
  end

  def load(json_string) when is_binary(json_string) do
    Jason.decode!(json_string)
    |> ExJsonSchema.Schema.resolve()
  end

  def load(failure) do
    Logger.error("Can not load #{failure}")
    %{}
  end
end
