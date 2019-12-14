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
      {:freedom_formatter, "~> 1.0", only: :dev},
      {:dialyxir, "~> 1.0.0-rc.7", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:credo, "~> 1.1.0", runtime: false}, 
    ]
  end
end
