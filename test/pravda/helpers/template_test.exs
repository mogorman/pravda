defmodule Pravda.Helpers.TemplateTest do
  use ExUnit.Case

  alias Pravda.Helpers.Template

  test "Unmatched calls generate generic error" do
    stock_message = Template.get_stock_message(nil, nil)
    stock_message2 = Template.get_stock_message(7, 2)
    assert(stock_message == stock_message2)
  end

  test "Not found generate generic error" do
    stock_message = Template.get_stock_message(:not_found, nil)
    stock_message2 = Template.get_stock_message(:not_found, %{"reasons" => [%{"error" => "anything"}]})
    assert(stock_message == stock_message2)
  end

  test "invalid body  generate generic error" do
    object_errors = [%{"error" => "failure"}]
    object = {"GET", "SOME_URL", object_errors}
    stock_message = Template.get_stock_message(:invalid_body, object)
    description = stock_message["message"]["description"]
    errors = stock_message["message"]["user_info"]["json_value"]["validation_errors"]
    assert(description == "Body input did not match schema")
    assert(object_errors == errors)
  end

  test "invalid params  generate generic error" do
    object_errors = [%{"error" => "failure"}]
    object = {"GET", "SOME_URL", object_errors}
    stock_message = Template.get_stock_message(:invalid_params, object)
    description = stock_message["message"]["description"]
    errors = stock_message["message"]["user_info"]["json_value"]["validation_errors"]
    assert(description == "Params input did not match schema")
    assert(object_errors == errors)
  end

  test "invalid response generate generic error" do
    object_errors = [%{"error" => "failure"}, %{"error2" => "anotherer"}]
    object = {"GET", "SOME_URL", object_errors}
    stock_message = Template.get_stock_message(:invalid_response, object)
    description = stock_message["message"]["description"]
    errors = stock_message["message"]["user_info"]["json_value"]["validation_errors"]
    assert(description == "Server response did not match schema")
    assert(object_errors == errors)
  end
end
