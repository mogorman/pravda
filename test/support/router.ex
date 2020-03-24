defmodule PravdaTest.Router do
  use Phoenix.Router
  require Pravda.Loader
  alias PravdaTest.{PetsController, PravdaCustom, PravdaError, PravdaMigrations}

  pipeline :api do
    plug(:accepts, ["json"])

    plug(Pravda,
      all_paths_required: true,
      spec_var: "spec-version",
      error_callback: PravdaError,
      custom_error_callback: PravdaCustom,
      migration_callback: PravdaMigrations,
      specs: Pravda.Loader.read_dir("test/specs")
    )
  end

  pipeline :api_dont_validate_output do
    plug(:accepts, ["json"])

    plug(Pravda,
      name: :api_dont_validate_output,
      all_paths_required: true,
      spec_var: "spec-version",
      spec_var_placement: :body,
      error_callback: PravdaError,
      migration_callback: PravdaMigrations,
      validate_response: false,
      specs: Pravda.Loader.read_dir("test/specs")
    )
  end

  pipeline :api_skip do
    plug(:accepts, ["json"])

    plug(Pravda,
      name: :skip,
      all_paths_required: true,
      spec_var: "spec-version",
      validate_response: false,
      error_callback: PravdaError,
      migrate_input: false,
      migrate_output: false,
      specs: Pravda.Loader.read_dir("test/specs")
    )
  end

  pipeline :api_dont_migrate do
    plug(:accepts, ["json"])

    plug(Pravda,
      name: :dont_migrate,
      all_paths_required: true,
      spec_var: "spec-version",
      spec_var_placement: :query,
      error_callback: PravdaError,
      migrate_input: false,
      migrate_output: false,
      specs: Pravda.Loader.read_dir("test/specs")
    )
  end

  pipeline :api_function do
    plug(:accepts, ["json"])

    plug(Pravda,
      name: :function,
      all_paths_required: true,
      spec_var: "spec-version",
      migration_callback: PravdaMigrations,
      specs: Pravda.Loader.read_dir("test/specs")
    )
  end

  pipeline :api_invalid do
    plug(:accepts, ["json"])

    plug(Pravda,
      name: :invalid,
      allow_invalid_input: true,
      all_paths_required: true,
      spec_var: "spec-version",
      migration_callback: PravdaMigrations,
      specs: Pravda.Loader.read_dir("test/specs")
    )
  end

  pipeline :api_disabled do
    plug(:accepts, ["json"])
    plug(Pravda, enable: false)
  end

  pipeline :api_disabled_all do
    plug(:accepts, ["json"])

    plug(Pravda,
      enable: true,
      all_paths_required: false,
      validate_params: false,
      validate_body: false,
      validate_response: false,
      migrate_input: false,
      migrate_output: false
    )
  end

  pipeline :api_disabled_path_required do
    plug(:accepts, ["json"])

    plug(Pravda,
      enable: true,
      all_paths_required: true,
      validate_params: false,
      validate_body: false,
      validate_response: false,
      migrate_input: false,
      migrate_output: false
    )
  end

  scope "/pravda" do
    pipe_through(:api)
    post("/pets", PetsController, :index)
  end

  scope "/pravda_disabled" do
    pipe_through(:api_disabled)
    get("/pets", PetsController, :index)
  end

  scope "/pravda_disabled_all" do
    pipe_through(:api_disabled_all)
    get("/pets", PetsController, :index)
  end

  scope "/pravda_disabled_path_required" do
    pipe_through(:api_disabled_path_required)
    get("/pets", PetsController, :index)
  end

  scope "/pravda_function" do
    pipe_through(:api_function)
    post("/pets", PetsController, :index)
  end

  scope "/pravda_invalid" do
    pipe_through(:api_invalid)
    post("/pets", PetsController, :index)
  end

  scope "/pravda_skip" do
    pipe_through(:api_skip)
    post("/pets", PetsController, :index)
  end

  scope "/pravda_dont_migrate" do
    pipe_through(:api_dont_migrate)
    post("/pets", PetsController, :index)
  end

  scope "/pravda_dont_validate_output" do
    pipe_through(:api_dont_validate_output)
    post("/pets", PetsController, :index)
  end
end
