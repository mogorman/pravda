defmodule PravdaTest do
  use ExUnit.Case, async: true
  use Plug.Test

  require Pravda.Loader

  doctest Pravda

  test "stupid version test to satisfy coveralls" do
    version = Pravda.version()
    assert(Version.parse(version) != :error)
  end

  test "stupid init test to satisfy coveralls" do
    opts = [spec_var_placement: :query]
    map_opts = %{enable: false}
    assert(Pravda.init(opts) == [spec_var_placement: :query, specs: %{}, name: Pravda.DefaultName])
    assert(Pravda.init(map_opts) == [enable: false, specs: %{}, name: Pravda.DefaultName])
    opts = [spec_var_placement: :query, specs: Pravda.Loader.read_dir("test/specs")]
    new_opts = Pravda.init(opts)
    assert(Keyword.get(new_opts, :specs) != Keyword.get(opts, :specs))
  end

  test "test disabled pravda does nothing" do
    conn =
      conn(:get, "/pravda_disabled/pets")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert(Poison.decode!(conn.resp_body) == %{"pravda_pet" => "asdf"})
    assert conn.status == 200
  end

  test "test pravda does nothing when all things disabled" do
    conn =
      conn(:get, "/pravda_disabled_all/pets")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert(Poison.decode!(conn.resp_body) == %{"pravda_pet" => "asdf"})
    assert conn.status == 200
  end

  test "test pravda rejects when no matching path found" do
    conn =
      conn(:get, "/pravda_disabled_path_required/pets")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert(
      Poison.decode!(conn.resp_body) == %{
        "message" => %{"description" => "Schema not implemented", "title" => "Failed"}
      }
    )

    assert conn.status == 501
  end

  test "test pravda validation" do
    conn =
      conn(:post, "/pravda/pets", %{"name" => "a dog name", "photoUrls" => []})
      |> put_req_header("content-type", "application/json")
      |> put_req_header("doggie", "im a dawg")
      |> PravdaTest.Router.call([])

    assert(Poison.decode!(conn.resp_body) == %{"pravda_pet" => "asdf", "old_key" => true})
    assert conn.status == 200
  end

  test "test pravda validation with down migration" do
    conn =
      conn(:post, "/pravda/pets", %{"name" => "a dog name", "photoUrls" => []})
      |> put_req_header("content-type", "application/json")
      |> put_req_header("spec-version", "1.0.0")
      |> put_req_header("doggie", "im a dawg")
      |> PravdaTest.Router.call([])

    assert(Poison.decode!(conn.resp_body) == %{"pravda_pet" => "asdf", "old_key" => true})
    assert conn.status == 200
  end

  test "test pravda validation fails param" do
    conn =
      conn(:post, "/pravda/pets", %{"name" => "a dog name", "photoUrls" => []})
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 400
  end

  test "test pravda validation fails body" do
    conn =
      conn(:post, "/pravda/pets", %{"name" => 5, "photoUrls" => []})
      |> put_req_header("doggie", "im a dawg")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 400
  end

  test "test pravda validation fails response" do
    conn =
      conn(:post, "/pravda/pets", %{"name" => "FAIL", "photoUrls" => []})
      |> put_req_header("doggie", "im a dawg")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 500
  end

  test "test pravda validation fails when cant find status code" do
    conn =
      conn(:post, "/pravda/pets", %{"name" => "FAIL2", "photoUrls" => []})
      |> put_req_header("doggie", "im a dawg")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 500
  end

  test "test pravda validation callback function works" do
    Application.put_env(:pravda, :function, %{error_callback: fn _errors, _conn, _opts -> nil end})

    conn =
      conn(:post, "/pravda_function/pets", %{"name" => "FAIL", "photoUrls" => []})
      |> put_req_header("doggie", "im a dawg")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 500
  end

  test "test pravda allows invalid output" do
    Application.put_env(:pravda, :invalid, %{allow_invalid_output: true})

    conn =
      conn(:post, "/pravda_invalid/pets", %{"name" => "FAIL", "photoUrls" => []})
      |> put_req_header("doggie", "im a dawg")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 200
  end

  test "test pravda allows invalid input" do
    conn =
      conn(:post, "/pravda_invalid/pets", %{"name" => "a dog name", "photoUrls" => []})
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 200
  end

  test "test pravda skips output validation" do
    conn =
      conn(:post, "/pravda_skip/pets", %{"name" => "FAIL", "photoUrls" => []})
      |> put_req_header("doggie", "im a dawg")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 200
  end

  test "test pravda dont migrate" do
    conn =
      conn(:post, "/pravda_dont_migrate/pets?spec-version=2.0.0", %{"name" => "pet", "photoUrls" => []})
      |> put_req_header("doggie", "im a dawg")
      |> put_req_header("new-header", "done")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 200
  end

  test "test pravda doesnt validate output" do
    conn =
      conn(:post, "/pravda_dont_validate_output/pets", %{"name" => "FAIL", "photoUrls" => [], "spec-version" => "2.0.0"})
      |> put_req_header("doggie", "im a dawg")
      |> put_req_header("new-header", "done")
      |> put_req_header("content-type", "application/json")
      |> PravdaTest.Router.call([])

    assert conn.status == 200
  end
end
