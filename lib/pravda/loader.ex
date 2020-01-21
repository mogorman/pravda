defmodule Pravda.Loader do
  require Logger

  defmacro read_file(file_name) do
    File.read!(file_name)
  end

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
