# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md
@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/web-command.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/documentation-guidelines.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/elixir-patterns.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/library-design.md

## Project Overview

Elixir library providing reusable infrastructure for building API proxy/cache services. Published to Hex as `api_toolkit` under the ZenHive GitHub org. Current version: 0.1.0 (initial release 2026-03-30).

## Commands

```bash
mix test                          # Run all tests
mix test test/api_toolkit/cache_test.exs  # Run single test file
mix test test/api_toolkit/cache_test.exs:42  # Run single test at line
mix test.json                     # AI-friendly JSON test output
mix dialyzer                      # Type checking
mix dialyzer.json                 # AI-friendly dialyzer output
mix credo                         # Linting
mix sobelow                       # Security analysis
mix doctor                        # Doc/spec coverage checks
mix format                        # Format code (uses Styler plugin)
```

## Architecture

Six composable modules, no runtime dependencies between them:

- **`ApiToolkit.Cache`** - GenServer wrapping a named ETS table with TTL. Periodic cleanup via `Process.send_after`. Public ETS reads bypass the GenServer for concurrency.
- **`ApiToolkit.RateLimiter`** - Token bucket GenServer for outbound throttling. Multiple named instances via `child_spec/1` with `:name` as child id. Callers block via `:queue` when tokens exhausted; served FIFO on refill.
- **`ApiToolkit.InboundLimiter`** - Per-key inbound rate limiter using ETS with sliding window approximation. `check/2` is a direct ETS operation (no GenServer call). GenServer only handles periodic cleanup of stale entries. Config stored in `:persistent_term` for zero-cost hot path reads. Per-node only; see moduledoc for multi-node deployment notes.
- **`ApiToolkit.Metrics`** - GenServer owning a `write_concurrency: true` ETS table. Atomic counter updates via `ets:update_counter` — no GenServer bottleneck on writes.
- **`ApiToolkit.Provider`** - Behaviour + macro module. `use ApiToolkit.Provider` + `defapi/2` accumulates endpoint metadata at compile time via `@before_compile`. Generates `provider_info/0`, `endpoints/0`, `describe/1`, and `indicators/0`. TTL is runtime-configurable via `{PROVIDER_NAME}_CACHE_TTL_MS` env var.
- **`ApiToolkit.Discovery`** - Macro-only module. `use ApiToolkit.Discovery, providers: [...]` generates 8 discovery functions (providers, all_endpoints, describe, help, search, by_provider, categories, by_category) by calling into Provider callbacks at runtime.

**Key pattern**: Provider defines endpoints via `defapi` macro, Discovery aggregates multiple Providers. Consumer apps `use` both to get a self-documenting API surface.

**Self-describing API (Descripex)**: The 4 infrastructure modules (Cache, RateLimiter, InboundLimiter, Metrics) use `api()` macro annotations for machine-readable introspection. The root `ApiToolkit` module uses `Descripex.Discoverable` for progressive disclosure: `ApiToolkit.describe/0` (overview), `describe/1` (module functions), `describe/2` (function detail).

## Test Support

Test support modules live in `test/support/` (compiled only in `:test` via `elixirc_paths`):
- `TestProvider` - Sample provider with two endpoints (search, detail)
- `OtherTestProvider` - Second provider for multi-provider Discovery tests
- `TestDiscovery` - Discovery module aggregating both test providers

## Quality Gates

Doctor config (`.doctor.exs`) enforces:
- 100% moduledoc coverage
- 90% overall doc coverage
- 80% overall spec coverage
- Struct type specs required
