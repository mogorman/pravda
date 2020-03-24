defmodule Pravda.Config do
  @moduledoc false

  @defaults [
    name: Pravda.DefaultName,
    specs: [],
    enable: true,
    spec_var: "spec-var",
    spec_var_placement: :header,
    migration_callback: nil,
    error_callback: nil,
    custom_error_callback: nil,
    all_paths_required: true,
    explain_error: true,
    validate_params: true,
    validate_body: true,
    validate_response: true,
    allow_invalid_input: false,
    allow_invalid_output: false,
    migrate_input: true,
    migrate_output: true,
    fallback_to_latest: false
  ]

  defp default(key), do: @defaults[key]

  @doc ~S"""
  Returns the most specific non-nil config value it can, checking
  `opts`, `Application.get_env(:pravda, name)`,
  `Application.get_all_env(:pravda)`, and `@defaults` (in that order).
  Returns `nil` if nothing was found.
  """
  @spec config(atom, Keyword.t()) :: any
  def config(key, opts \\ []) do
    cond do
      nil != (value = opts[key]) -> value
      nil != (value = Application.get_env(:pravda, opts[:name])[key]) -> value
      nil != (value = Application.get_env(:pravda, key)) -> value
      :else -> default(key)
    end
  end
end
