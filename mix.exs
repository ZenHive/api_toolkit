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
      aliases: aliases(),
      dialyzer: dialyzer(),
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
      {:descripex, "~> 0.12"},

      # HTTP middleware — needed by Plug.RemoteIp, Plug.RateLimit, Router.Helpers
      {:plug, "~> 1.16"},

      # Machine Payments Protocol — owns the MCP payment transport ApiToolkit.MCP.Payment
      # gates on top of. Required, not optional: marking it optional would buy a
      # configuration this suite can never exercise (mpp is always present here) while
      # forcing lib/ to avoid MPP structs and types — a constraint that only breaks at a
      # consumer's build. If the on-chain tree it pulls ever becomes a real burden, the
      # fix is to split the payment layer into its own package, not to loosen this.
      {:mpp, "~> 0.14"},

      # Dev/test tooling — AI-friendly output
      {:ex_unit_json, "~> 0.6.0", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2.1", only: [:dev, :test], runtime: false},

      # Formatting + static analysis
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      # ex_ast held at 0.12.x by reach 2.8 (requires ex_ast ~> 0.12.0); latest is 0.13.1.
      {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},

      # Runtime introspection MCP server (non-Phoenix — needs its own HTTP server)
      {:tidewave, "~> 0.9.0", only: :dev},
      {:bandit, "~> 1.12", only: :dev}
    ]
  end

  defp aliases do
    [
      # TagTODO/TagFIXME stay on in .credo.exs for visibility (`mix credo` shows them);
      # the gate excludes them so it fails only on real regressions, not tracked debt.
      "check.fast": [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore TagTODO,TagFIXME"
      ],
      # Manual / CI gate (NOT run by the commit hook). Drops dialyzer; keeps tests + sobelow + doctor.
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore TagTODO,TagFIXME",
        "doctor --raise",
        # `preferred_envs` (cli/0) is ignored for alias steps — set MIX_ENV explicitly.
        "cmd env MIX_ENV=test mix test.json --quiet --cover --cover-threshold 85 --summary-only --exclude integration",
        # --skip honors .sobelow-skips / inline annotations; library ships Plug modules.
        "sobelow --skip",
        # Fails when AGENTS.md has drifted from its CLAUDE.md source.
        "cmd sh -c \"$HOME/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh --check\""
      ],
      # CI mirror — adds dialyzer. Matches `elixir-ci-harness` `harness.yml`.
      "precommit.full": ["precommit", "dialyzer.json --quiet"],
      # Standalone Tidewave MCP server (non-Phoenix). Port 4032 — see ~/.claude/tidewave-ports.md.
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4032) end)'"
      ]
    ]
  end

  defp dialyzer do
    [
      # OOM mitigation: skip transitive deps (default is :app_tree).
      # Tidewave/bandit's HTTP stack (finch, mint, thousand_island, websock, ...)
      # is not in lib/'s call graph and bloats the PLT by hundreds of modules.
      plt_add_deps: :apps_direct,
      # :plug_crypto is transitive via :plug but IS called directly
      # (MCP.Payment -> Plug.Crypto.secure_compare/2), so :apps_direct must re-add it.
      plt_add_apps: [:mix, :plug_crypto],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      ignore_warnings: ".dialyzer_ignore.exs"
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
