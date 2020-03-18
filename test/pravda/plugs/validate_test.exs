defmodule Pravda.Plugs.ValidateTest do
  use ExUnit.Case
  doctest Pravda.Plugs.Validate
  require Pravda.Loader

  import ExUnit.CaptureLog
  import Mock

  alias Pravda.Plugs.Validate

  defmodule FakeRouter do
    def __match_route__("GET", ["pet", "44"], _) do
      {%{
         conn: nil,
         log: :debug,
         path_params: %{"petId" => "44"},
         pipe_through: [:accept_json],
         plug_opts: :get,
         route: "/pet/:petId"
       }, fn -> nil end, fn -> nil end, {nil, nil}}
    end

    def __match_route__(method, path, host) do
      :error
    end
  end

  def build_fake_conn(method, url, path_params) do
    %{
      assigns: %{},
      body_params: %{},
      method: method,
      host: "localhost",
      params: %{},
      path_info: [],
      path_params: path_params,
      private: %{
        :phoenix_router => FakeRouter
      },
      query_params: %{},
      query_string: "",
      remote_ip: {127, 0, 0, 1},
      req_cookies: [],
      req_headers: [],
      request_path: url
    }
  end

  test "validate init with no args returns nil" do
    assert capture_log([level: :error], fn ->
             assert is_nil(Validate.init([]))
           end) =~ "specs are required but were not provided."
  end

  test "validate init" do
    assert(is_map(Validate.init(%{specs: [Pravda.Loader.read_file("test/petstore.json")]})))
  end

  test "validate call" do
    with_mock Plug.Conn,
      fetch_query_params: fn conn -> conn end,
      register_before_send: fn conn, _ -> conn end,
      put_req_header: fn conn, var_name, value -> conn end,
      get_req_header: fn conn, var_name -> [] end do
      opts =
        %{error_callback: fn _, _, _ -> nil end, specs: [Pravda.Loader.read_file("test/petstore.json")]}
        |> Validate.init()

      conn = build_fake_conn("GET", "/pet/44", %{"petId" => "44"})
      Validate.call(conn, opts)
    end
  end

  test "fail to match call" do
    with_mock Plug.Conn,
      fetch_query_params: fn conn -> conn end,
      register_before_send: fn conn, _ -> conn end,
      put_resp_header: fn conn, _, _ -> conn end,
      get_req_header: fn conn, var_name -> [] end,
      put_req_header: fn conn, var_name, value -> conn end,
      resp: fn conn, _, _ -> conn end,
      halt: fn conn -> conn end do
      opts =
        %{
          error_callback: fn _, _, _ -> nil end,
          all_paths_required: true,
          specs: [Pravda.Loader.read_file("test/petstore.json")]
        }
        |> Validate.init()

      conn = build_fake_conn("GET", "/human/44", %{"humanId" => "44"})

      assert capture_log([level: :error], fn ->
               Validate.call(conn, opts)
             end) =~ "No schema found for GET:/human/44"
    end
  end

  test "fail to match callbut allowed" do
    with_mock Plug.Conn,
      fetch_query_params: fn conn -> conn end,
      register_before_send: fn conn, _ -> conn end,
      put_resp_header: fn conn, _, _ -> conn end,
      get_req_header: fn conn, var_name -> [] end,
      put_req_header: fn conn, var_name, value -> conn end,
      resp: fn conn, _, _ -> conn end,
      halt: fn conn -> conn end do
      opts =
        %{all_paths_required: false, specs: [Pravda.Loader.read_file("test/petstore.json")]}
        |> Validate.init()

      conn = build_fake_conn("GET", "/human/44", %{"humanId" => "44"})

      assert capture_log([level: :info], fn ->
               Validate.call(conn, opts)
             end) =~ "No schema found for GET:/human/44"
    end
  end
end
