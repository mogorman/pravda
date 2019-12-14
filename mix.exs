defmodule Pravda.MixProject do
  use Mix.Project

  def project do
    [
      app: :pravda,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
      ],
      dialyzer: [
        plt_add_deps: :transitive,
        plt_add_apps: [:ex_unit, :mix],
      ],
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:freedom_formatter, "~> 1.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.0.0-rc.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: [:dev, :test]},
      {:credo, "~> 1.1.0", runtime: false},
    ]
  end
end
