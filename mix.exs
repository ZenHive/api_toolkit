defmodule ApiToolkit.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ZenHive/api_toolkit"

  def project do
    [
      app: :api_toolkit,
      version: @version,
      description: "Reusable infrastructure for building API proxy and cache services in Elixir.",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "ApiToolkit",
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/api_toolkit"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [preferred_envs: ["test.json": :test, "dialyzer.json": :dev]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_unit_json, ">= 0.4.0", only: [:dev, :test], runtime: false},
      {:dialyzer_json, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:styler, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:doctor, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/api_toolkit"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end
end
