# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@~/.claude/includes/critical-rules.md

Everything else is skill-on-demand per the Elixir Library template in
`~/.claude/setup-guide.md` — `elixir:ex-unit-json`, `elixir:dialyzer-json`,
`elixir:code-style`, `elixir:development-philosophy`,
`elixir:development-commands`, `elixir:elixir-setup`, `tasks:*`,
`workflow:*`. Invoke the owning skill before acting in its domain rather than
eager-importing its include (double-loading pays twice for the same tokens).

## Project Overview

Elixir library providing reusable infrastructure for building API proxy/cache services. Published to Hex as `api_toolkit` under the ZenHive GitHub org. Current version: 0.1.0 (initial release 2026-03-30).

## Toolchain & check commands

**The canonical gate is `mix precommit.full`.** It runs the full `precommit`
alias (format check, `compile --warnings-as-errors`, `credo --strict`,
`doctor --raise`, `mix test.json` with the coverage gate, `sobelow --skip`,
and the `AGENTS.md` freshness check) and then adds `mix dialyzer.json`. Run it
before opening a PR or handing work to a reviewer. `mix precommit` is the
faster manual gate without dialyzer; `mix check.fast` is the seconds-long
inner-loop trio (format · compile · credo).

```bash
mix precommit.full                # canonical gate (CI mirror) — run before PR/handoff
mix precommit                     # same minus dialyzer
mix check.fast                    # format + compile --warnings-as-errors + credo --strict
mix test.json --quiet             # AI-friendly JSON test output (failures only)
mix test.json --quiet --failed    # re-run only previously failed tests
mix test test/api_toolkit/cache_test.exs:42   # single test at a line
mix dialyzer.json --quiet         # AI-friendly JSON dialyzer output
mix dialyzer                      # authoritative dialyzer fallback (human format)
mix credo --strict                # linting
mix sobelow --skip                # security analysis (honors .sobelow-skips)
mix doctor                        # doc/spec coverage checks
mix format                        # format code (Styler plugin)
mix tidewave                      # standalone Tidewave MCP server on port 4032
```

### 🚨 `mix test.json` and `mix dialyzer.json` emit JSON BY DESIGN

These are the `ex_unit_json` and `dialyzer_json` reporters, not broken builds.
A wall of JSON on stdout is the **expected, successful** output shape.

- **Parse the JSON for real failures.** For tests: `summary.result` and the
  `tests[]` entries with `state: "failed"` (a healed flake moves to `flaky[]`
  and does not block). For dialyzer: `warnings[]` and `summary.total`.
- **Never flag the JSON envelope itself as a build error** and never reject a
  run because "the output looks like a dump". Exit code 2 with valid JSON means
  *findings*, not *crash*.
- **Plain `mix dialyzer` is the authoritative fallback** when the JSON encoder
  can't serialize a warning shape — if `dialyzer.json` output looks truncated
  or malformed, re-run `mix dialyzer` and treat its human-readable output as
  the verdict.
- Large output: always `--output /tmp/x.json` and slice with `jq`, rather than
  piping a whole suite into the transcript.

The same rule applies to any future JSON-emitting check task this repo adds.

### MCP servers (all four agent families)

Tidewave runs as a standalone Bandit server on **port 4032** (`mix tidewave`,
then `iex -S mix tidewave` for an interactive node). The MCP config is mirrored
across all four agent families and must stay in sync — same server set, same
URL — whenever a server is added, removed, or re-ported:

| Agent  | File                 |
|--------|----------------------|
| Claude | `.mcp.json`          |
| Cursor | `.cursor/mcp.json`   |
| Codex  | `.codex/config.toml` |
| Grok   | `.grok/config.toml`  |

Port registry: `~/.claude/tidewave-ports.md`. After editing source, call
`recompile()` through `project_eval` — the Tidewave node holds the old bytecode
otherwise.

## Architecture

Nineteen composable modules across five layers, plus the root `ApiToolkit`
facade module:

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
- **`ApiToolkit.MCP.Server`** - Behaviour defining the contract for MCP handlers. Required callbacks: `tools/0` (tool definitions with name, description, inputSchema, callback) and `server_info/0`. Optional callbacks for resources, prompts, custom capabilities, and payment config.
- **`ApiToolkit.MCP.Handler`** - Pure-function JSON-RPC 2.0 dispatch. Takes decoded message map + handler module, returns response tuple. Handles: `initialize` (version negotiation, protocol `2025-03-26`), `ping`, `tools/list`, `tools/call` (with payment gating + exception catching → `isError: true`), `resources/list`, `resources/read`, `prompts/list`, `prompts/get`, and notifications. Full batch support via `handle_batch/3`. Transport-agnostic. Payment interception via `maybe_gate_payment/6` checks assigns for `:mpp_payment` config.
- **`ApiToolkit.MCP.Plug`** - HTTP transport layer. `@behaviour Plug` that reads parsed JSON body (single or batch array), delegates to Handler, sends 200/202/400 responses. POST-only (405 for other methods). Configurable: `:handler` (required), `:assigns` (optional context for arity-2 tool callbacks). Auto-detects `payment_config/0` on the handler and injects into assigns as `:mpp_payment`.
- **`ApiToolkit.MCP`** - `use ApiToolkit.MCP` macro generates a complete `MCP.Server` implementation from a Discovery module. Options: `:discovery`, `:server_info`, `:strip_prefixes`, `:tool_name`, `:tiers`, `:resources`, `:prompts`, `:payment`. Generates `tools/0`, `server_info/0`, `dispatch_map/0`, and optionally `resources/0`, `read_resource/1`, `prompts/0`, `get_prompt/2`, `capabilities/0`, `payment_config/0`. Resources declare a `:read` function; prompts declare a `:handler` function. Payment declares MPP method config. Private helper functions (`__mcp_resources__/0`, `__mcp_prompts__/0`) hold the raw definitions with anonymous functions at runtime.
- **`ApiToolkit.MCP.ToolBuilder`** - Pure-function module converting Provider/Discovery endpoints into MCP tool definitions. Path-based naming (`/api/hex/encode` → `hex_encode`), JSON Schema generation from Provider params, Provider→MCP result translation (strips cache TTL, maps errors). `dispatch_map/2` returns `%{tool_name => {module, function, tier}}` for payment layer tier lookup.
- **`ApiToolkit.MCP.Payment`** - Per-tool payment gating for MCP JSON-RPC transport. The MPP protocol itself is delegated to `MPP.Mcp` (mpp 0.14): challenge generation, HMAC binding, JCS canonicalization, credential verification, replay protection, receipt attachment, and JSON-RPC error shaping (`-32042` Payment Required, `-32602` malformed credential, `-32043` verification failed, each with RFC 9457 problem details). This module owns only what MPP has no concept of: tier gating via `requires_payment?/2` (fail-closed — a tool is free only on an explicit non-`:paid` tier), `capabilities/1` for the `initialize` response, `generate_challenges/1` for advertising prices outside a 402, and optional rejection recording. `init/1` forwards to `MPP.Mcp.init/1` and carries the api_toolkit-only `:rejections` alongside. Replay protection is on by default; a paid tool that fails still consumes the credential and still gets its receipt.

**Agent Discovery:**
- **`ApiToolkit.Homepage`** - Pure-function module generating a plain-text homepage from Discovery metadata. `render/2` takes a Discovery module + opts (`:name`, `:version`, `:description`, `:url`, `:discovery_paths`, `:group_by`, `:group_labels`). Configurable endpoint grouping via `:group_by` function — no hardcoded tier concept. Formats GET endpoints with example query strings from param `:example` metadata.
- **`ApiToolkit.LLMs`** - Pure-function module generating Markdown documentation optimized for LLM consumption. `render/2` mirrors Homepage's API (same opts) plus `:pricing` (function returning per-endpoint pricing text or nil). Renders full parameter documentation (type, required, description, examples), example GET request URLs, and a Discovery footer. Designed for `llms.txt` endpoints.
- **`ApiToolkit.OpenAPI`** - Pure-function module generating OpenAPI 3.1 documents from Discovery metadata. `render/2` returns a JSON-serializable map. Same base opts as Homepage/LLMs plus `:pricing` (function returning `%{amount, currency, method}` or nil for `x-payment-info` extensions), `:contact`, `:license`, `:categories`, `:docs` (for `x-service-info`). GET endpoints → query parameters; POST → requestBody with JSON schema. Type mapping: `:string`→string, `:integer`→integer, `:float`→number, `:boolean`→boolean, `:array`→array of strings.

**Key pattern**: Provider defines endpoints via `defapi` macro, Discovery aggregates multiple Providers. Consumer apps `use` both to get a self-documenting API surface. Plug modules compose in a pipeline: RemoteIp → RateLimit → Router dispatch via Helpers. MCP Server exposes tools via JSON-RPC — consumers implement the `MCP.Server` behaviour and forward `/mcp` to `MCP.Plug`.

**Self-describing API (Descripex)**: The five infrastructure modules (Cache, RateLimiter, InboundLimiter, Metrics, Rejections) `use Descripex` with `api()` macro annotations for machine-readable introspection. The root `ApiToolkit` module uses `Descripex.Discoverable` for progressive disclosure: `ApiToolkit.describe/0` (overview), `describe/1` (module functions), `describe/2` (function detail). Its registered module list currently covers Cache, RateLimiter, InboundLimiter, and Metrics — Rejections is annotated but not yet registered there.

## Test Support

Test support modules live in `test/support/` (compiled only in `:test` via `elixirc_paths`):
- `TestProvider` - Sample provider with two endpoints (search, detail)
- `OtherTestProvider` - Second provider for multi-provider Discovery tests
- `TestDiscovery` - Discovery module aggregating both test providers
- `TestMCPHandler` - MCP handler with six tools (echo, greet, crash, bad_return, structured, with_meta) for protocol tests. Also defines `TestMCPHandlerResourcesOnly` and `TestMCPHandlerPromptsOnly` for capability gating tests
- `TestMCPHandlerFull` - MCP handler implementing all optional callbacks (resources, read_resource, prompts, get_prompt) for success path tests
- `TestMCPToolsHandler` - MCP handler generated via `use ApiToolkit.MCP` from TestDiscovery for tool registration DSL tests
- `TestMCPCustomNameHandler` - MCP handler generated via `use ApiToolkit.MCP` with a custom `:tool_name` function (`custom_<function>`) for tool-naming tests
- `TestMCPResourcesPromptsHandler` - MCP handler generated via `use ApiToolkit.MCP` with `:resources` and `:prompts` options for macro registration tests
- `TestPaymentMethod` - Stub `MPP.Method` for payment gating tests. Accepts `"valid"` token, rejects all others
- `TestPaymentProvider` - Client-side `MPP.Client.PaymentProvider` stub paying any `test`/`charge` challenge. Drives the `MPP.Client.MCP` interop test that proves our challenges are consumable by MPP's own client
- `TestMCPPaymentHandler` - MCP handler generated via `use ApiToolkit.MCP` with `:payment` and `:tiers` options. TestProvider is `:paid`, OtherTestProvider is `:free`
- `HomepageTestProvider` - Provider with POST endpoint and `:example` params for Homepage rendering tests. Defines nested `HomepageTestProvider.Discovery`

## Git Commit Configuration

**Configured**: 2026-03-30

### Commit Message Format

**Format**: imperative-mood

#### Imperative Mood Template
```
<description>
```
Start with imperative verb: Add, Update, Fix, Remove, etc.

## Quality Gates

Doctor config (`.doctor.exs`) enforces:
- 100% overall moduledoc coverage
- 90% overall doc coverage, 75% per module
- 80% overall spec coverage, 50% per module
- Struct type specs required
- `ApiToolkit.MCP` and `ApiToolkit.Provider` are in `ignore_modules` (macro-generated surface)

`mix precommit` runs `doctor --raise`, which overrides the config's
`raise: false` so the gate actually fails on a regression.
