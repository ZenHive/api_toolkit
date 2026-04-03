defmodule ApiToolkit.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ZenHive/api_toolkit"

  def project do
    [
      app: :api_toolkit,
      version: @version,
      description: "Reusable infrastructure for building API proxy and cache services in Elixir.",
      elixir: "~> 1.18",
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
      # Self-describing APIs — full dep (not dev/test only), macros expand at compile time
      {:descripex, "~> 0.6"},

      # HTTP middleware — needed by Plug.RemoteIp, Plug.RateLimit, Router.Helpers
      {:plug, "~> 1.16"},

      # Dev/test tooling
      {:ex_unit_json, ">= 0.4.0", only: [:dev, :test], runtime: false},
      {:dialyzer_json, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:styler, ">= 0.0.0", only: [:dev, :test], runtime: false},
      # TODO: Using git branch as workaround for Credo 1.7.x crash on Elixir 1.20-rc sigils.
      # Switch back to hex {:credo, ">= 0.0.0"} when a compatible release is published.
      {:credo, github: "rrrene/credo", branch: "release/1.7", only: [:dev, :test], runtime: false},
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
