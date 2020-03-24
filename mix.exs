defmodule Pravda.MixProject do
  use Mix.Project

  def project do
    [
      app: :pravda,
      version: "0.4.3",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/mogorman/pravda",
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_add_deps: :transitive,
        plt_add_apps: [:ex_unit, :mix]
      ],
      # Docs
      name: "Pravda",
      source_url: "https://github.com/mogorman/pravda",
      homepage_url: "https://github.com/mogorman/pravda",
      docs: [
        # The main page in the docs
        main: "Pravda",
        logo: "pravda.png",
        extras: ["README.md"]
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description() do
    "OpenAPI 3 phoenix plug based validation."
  end

  defp package() do
    [
      maintainers: ["Matthew O'Gorman mog@rldn.net"],
      links: %{"GitHub" => "https://github.com/mogorman/pravda"},
      licenses: ["MIT"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.4.0"},
      {:poison, "~> 3.1", only: [:test]},
      {:dialyxir, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: [:dev, :test]},
      {:credo, "~> 1.1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:jason, "~> 1.1"},
      {:plug, ">= 1.6.0"},
      {:ex_json_schema, "~> 0.7"},
      {:mojito, "~> 0.5.0"},
      {:telemetry, "~> 0.4.1"}
    ]
  end
end
