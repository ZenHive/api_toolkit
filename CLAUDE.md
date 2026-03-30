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

Fifteen composable modules across four layers:

**Infrastructure (GenServer + ETS):**
- **`ApiToolkit.Cache`** - GenServer wrapping a named ETS table with TTL. Periodic cleanup via `Process.send_after`. Public ETS reads bypass the GenServer for concurrency.
- **`ApiToolkit.RateLimiter`** - Token bucket GenServer for outbound throttling. Multiple named instances via `child_spec/1` with `:name` as child id. Callers block via `:queue` when tokens exhausted; served FIFO on refill.
- **`ApiToolkit.InboundLimiter`** - Per-key inbound rate limiter using ETS with sliding window approximation. `check/2` is a direct ETS operation (no GenServer call). GenServer only handles periodic cleanup of stale entries. Config stored in `:persistent_term` for zero-cost hot path reads. Per-node only; see moduledoc for multi-node deployment notes.
- **`ApiToolkit.Metrics`** - GenServer owning a `write_concurrency: true` ETS table. Atomic counter updates via `ets:update_counter` — no GenServer bottleneck on writes.
- **`ApiToolkit.Rejections`** - ETS-backed GenServer tracking rejection counts by type and path. Accepts any atom as rejection type. Named instances via `child_spec/1`. Same atomic-write pattern as Metrics.

**Plug Pipeline:**
- **`ApiToolkit.Plug.RemoteIp`** - Rewrites `conn.remote_ip` from a trusted reverse proxy header. Configurable header name (default: `fly-client-ip`). IPv4 + IPv6. No-op on missing/invalid header.
- **`ApiToolkit.Plug.RateLimit`** - Per-IP rate limiting wrapping `InboundLimiter`. Returns 429 + `Retry-After` + JSON body. Configurable: limiter name, skip paths, optional rejection recording.
- **`ApiToolkit.Router.Helpers`** - `handle_endpoint/3,4` dispatches to `module.function(params)` with JSON response + optional metrics. `merge_params/1` merges query + body params.

**Provider/Discovery DSL:**
- **`ApiToolkit.Provider`** - Behaviour + macro module. `use ApiToolkit.Provider` + `defapi/2` accumulates endpoint metadata at compile time via `@before_compile`. Generates `provider_info/0`, `endpoints/0`, `describe/1`, and `indicators/0`. TTL is runtime-configurable via `{PROVIDER_NAME}_CACHE_TTL_MS` env var.
- **`ApiToolkit.Discovery`** - Macro-only module. `use ApiToolkit.Discovery, providers: [...]` generates 8 discovery functions (providers, all_endpoints, describe, help, search, by_provider, categories, by_category) by calling into Provider callbacks at runtime.

**MCP Server (JSON-RPC 2.0):**
- **`ApiToolkit.MCP.Server`** - Behaviour defining the contract for MCP handlers. Required callbacks: `tools/0` (tool definitions with name, description, inputSchema, callback) and `server_info/0`. Optional callbacks for resources, prompts, and custom capabilities (extensibility for T3/T4).
- **`ApiToolkit.MCP.Handler`** - Pure-function JSON-RPC 2.0 dispatch. Takes decoded message map + handler module, returns response tuple. Handles: `initialize` (version negotiation, protocol `2025-03-26`), `ping`, `tools/list`, `tools/call` (with exception catching → `isError: true`), `resources/list`, `resources/read`, `prompts/list`, `prompts/get`, and notifications. Full batch support via `handle_batch/3`. Transport-agnostic.
- **`ApiToolkit.MCP.Plug`** - HTTP transport layer. `@behaviour Plug` that reads parsed JSON body (single or batch array), delegates to Handler, sends 200/202/400 responses. POST-only (405 for other methods). Configurable: `:handler` (required), `:assigns` (optional context for arity-2 tool callbacks).
- **`ApiToolkit.MCP`** - `use ApiToolkit.MCP` macro generates a complete `MCP.Server` implementation from a Discovery module. Options: `:discovery`, `:server_info`, `:strip_prefixes`, `:tool_name`, `:tiers`. Generates `tools/0`, `server_info/0`, and `dispatch_map/0`.
- **`ApiToolkit.MCP.ToolBuilder`** - Pure-function module converting Provider/Discovery endpoints into MCP tool definitions. Path-based naming (`/api/hex/encode` → `hex_encode`), JSON Schema generation from Provider params, Provider→MCP result translation (strips cache TTL, maps errors). `dispatch_map/2` returns `%{tool_name => {module, function, tier}}` for T3 payment layer.

**Key pattern**: Provider defines endpoints via `defapi` macro, Discovery aggregates multiple Providers. Consumer apps `use` both to get a self-documenting API surface. Plug modules compose in a pipeline: RemoteIp → RateLimit → Router dispatch via Helpers. MCP Server exposes tools via JSON-RPC — consumers implement the `MCP.Server` behaviour and forward `/mcp` to `MCP.Plug`.

**Self-describing API (Descripex)**: The 4 infrastructure modules (Cache, RateLimiter, InboundLimiter, Metrics) use `api()` macro annotations for machine-readable introspection. The root `ApiToolkit` module uses `Descripex.Discoverable` for progressive disclosure: `ApiToolkit.describe/0` (overview), `describe/1` (module functions), `describe/2` (function detail).

## Test Support

Test support modules live in `test/support/` (compiled only in `:test` via `elixirc_paths`):
- `TestProvider` - Sample provider with two endpoints (search, detail)
- `OtherTestProvider` - Second provider for multi-provider Discovery tests
- `TestDiscovery` - Discovery module aggregating both test providers
- `TestMCPHandler` - MCP handler with four tools (echo, greet, crash, bad_return) for protocol tests
- `TestMCPToolsHandler` - MCP handler generated via `use ApiToolkit.MCP` from TestDiscovery for tool registration DSL tests

## Quality Gates

Doctor config (`.doctor.exs`) enforces:
- 100% moduledoc coverage
- 90% overall doc coverage
- 80% overall spec coverage
- Struct type specs required
