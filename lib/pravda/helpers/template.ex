defmodule Pravda.Helpers.Template do
  @moduledoc """
  This handles the stock default templating for Pravda, outputting several stock error messages
  """

  @doc ~S"""
  Returns the http status code for a given class of error
  """
  @spec get_stock_code(atom()) :: integer()
  def get_stock_code(:not_found) do
    501
  end

  def get_stock_code(:invalid_body) do
    400
  end

  def get_stock_code(:invalid_params) do
    400
  end

  def get_stock_code(:invalid_response) do
    500
  end

  def get_stock_code(_anything) do
    500
  end

  def get_stock_message(:not_found, _error) do
    %{
      "message" => %{
        "title" => "Failed",
        "description" => "Schema not implemented",
      },
    }
  end

  @doc ~S"""
  Returns the response body for a given state
  """
  @spec get_stock_message(atom(), tuple()) :: map()
  def get_stock_message(:invalid_body, {_method, _url, errors}) do
    %{
      "message" => %{
        "title" => "Failed",
        "description" => "Body input did not match schema",
        "user_info" => %{"json_value" => %{"validation_errors" => errors}},
      },
    }
  end

  def get_stock_message(:invalid_params, {_method, _url, errors}) do
    %{
      "message" => %{
        "title" => "Failed",
        "description" => "Params input did not match schema",
        "user_info" => %{"json_value" => %{"validation_errors" => errors}},
      },
    }
  end

  def get_stock_message(:invalid_response, {_method, _url, errors}) do
    %{
      "message" => %{
        "title" => "Failed",
        "description" => "Server response did not match schema",
        "user_info" => %{"json_value" => %{"validation_errors" => errors}},
      },
    }
  end

  def get_stock_message(_anything, _error) do
    %{
      "message" => %{
        "title" => "Failed",
        "description" => "Pravda had an internal error",
      },
    }
  end
end
