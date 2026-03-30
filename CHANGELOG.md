# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **ApiToolkit.MCP** — `use ApiToolkit.MCP` macro generates a complete `MCP.Server` implementation from Discovery metadata. Zero-boilerplate: provide `:discovery` module and `:server_info`, get `tools/0`, `server_info/0`, and `dispatch_map/0` for free.

- **ApiToolkit.MCP.ToolBuilder** — Pure-function module converting Provider/Discovery endpoints into MCP tool definitions. Path-based tool naming (`/api/hex/encode` → `hex_encode`), JSON Schema generation from Provider params, result translation (strips cache TTL, maps Provider errors to MCP format). Dispatch map links tool names to `{module, function, tier}` tuples — extensibility seam for T3 payment layer.

### Fixed

- **MCP.Plug**: Handle `Plug.Parsers` wrapping of top-level JSON arrays as `%{"_json" => [...]}`. Previously, batch requests sent through a standard `Plug.Parsers` pipeline were routed as invalid single messages instead of being dispatched to `handle_batch/3`.

- **MCP.Plug**: Empty parsed JSON body (`"{}"`) now correctly returns -32600 (Invalid Request) instead of -32700 (Parse error). Previously, `body_params == %{}` fell through to raw body read, which failed because `Plug.Parsers` had already consumed the body stream.

- **MCP.Handler**: Version negotiation now follows MCP 2025-03-26 lifecycle spec. Server always responds with its supported `protocolVersion` — the client decides compatibility. Previously hard-rejected older versions with -32600.

- **MCP.Handler**: Capability advertisement now requires both listing AND operation callbacks. `resources` capability requires `resources/0` + `read_resource/1`; `prompts` requires `prompts/0` + `get_prompt/2`. Previously advertised capabilities based on listing callback alone.

- **MCP.Handler**: All `function_exported?` checks now use `Code.ensure_loaded/1` first, ensuring handler modules work regardless of BEAM loading order.

- **MCP.Handler**: Reject `initialize` requests inside JSON-RPC batches per MCP 2025-03-26 lifecycle spec. The `initialize` handshake must be a standalone request, not part of a batch.

### Added

- **Phase 3: MCP Server Framework** — Reusable MCP JSON-RPC 2.0 server infrastructure. Three modules:

  - **ApiToolkit.MCP.Server** — Behaviour defining the handler contract. Required callbacks: `tools/0` (tool definitions with name, description, inputSchema, callback) and `server_info/0`. Optional callbacks for resources, prompts, and custom capabilities — extensibility seams for T2 (tool registration DSL), T3 (MPP payment layer), and T4 (resource/prompt registration).

  - **ApiToolkit.MCP.Handler** — Pure-function JSON-RPC 2.0 dispatch. Handles all MCP protocol methods: `initialize` (version negotiation, protocol `2025-03-26`), `ping`, `tools/list`, `tools/call` (with exception catching → `isError: true`), `resources/list`, `resources/read`, `prompts/list`, `prompts/get`, and notifications (`initialized`, `cancelled`). Full JSON-RPC batch support (`handle_batch/3`). Transport-agnostic — no Plug dependency. Tool callbacks support arity 1 (stateless) and arity 2 (with assigns context). Robust input handling: non-map params coerced safely, unexpected tool return values caught with `isError`.

  - **ApiToolkit.MCP.Plug** — HTTP transport layer. POST-only Plug that reads parsed JSON body (single or batch array), delegates to Handler, and sends 200/202/400 responses. Consumers configure with `:handler` (required) and `:assigns` (optional context for arity-2 callbacks). Handles oversized bodies gracefully.

- **Descripex integration** - Added `api()` macro annotations to Cache, RateLimiter, InboundLimiter, and Metrics for machine-readable introspection (`__api__/0`, `__api__/1`). Root `ApiToolkit` module uses `Descripex.Discoverable` for progressive disclosure via `describe/0-2`.

- **Phase 2: Plug Infrastructure** — Extracted 4 reusable modules from Strip0x as configurable building blocks. Added `plug` as a runtime dependency.

  - **ApiToolkit.Plug.RemoteIp** — Rewrites `conn.remote_ip` from a trusted reverse proxy header. Configurable header name (default: `fly-client-ip`; also supports `cf-connecting-ip`, `x-real-ip`, etc.). IPv4 + IPv6 via `:inet.parse_address/1`, no-op on failure.

  - **ApiToolkit.Rejections** — ETS-backed GenServer tracking rejection counts by type and path. Accepts any atom as rejection type (not hardcoded). Named instances via `child_spec/1`. Atomic ETS writes on the hot path. Descripex annotations for introspection.

  - **ApiToolkit.Plug.RateLimit** — Configurable Plug wrapping `InboundLimiter`. Returns 429 + `Retry-After` header + JSON error body. Configurable limiter name, skip paths, and optional rejection recording via `Rejections`.

  - **ApiToolkit.Router.Helpers** — `handle_endpoint/3,4` dispatches to `module.function(params)` with JSON response and optional metrics recording. `merge_params/1` merges query + body params (body wins).

## [0.1.0] - 2026-03-30

Initial release. Published to [Hex](https://hex.pm/packages/api_toolkit/0.1.0).

### Added

- **ApiToolkit.Cache** - GenServer wrapping a named ETS table with TTL and periodic cleanup. Public ETS reads bypass the GenServer for concurrency.
- **ApiToolkit.RateLimiter** - Token bucket GenServer for outbound throttling. Multiple named instances via `child_spec/1`. Callers block via `:queue` when tokens exhausted.
- **ApiToolkit.InboundLimiter** - Per-key inbound rate limiter using ETS with sliding window approximation. Direct ETS reads, no GenServer bottleneck on hot path. Config via `:persistent_term`.
- **ApiToolkit.Metrics** - GenServer owning a `write_concurrency: true` ETS table. Atomic counter updates via `ets:update_counter`.
- **ApiToolkit.Provider** - Behaviour + macro module. `defapi/2` accumulates endpoint metadata at compile time. Generates `provider_info/0`, `endpoints/0`, `describe/1`, and `indicators/0`. Runtime-configurable TTL via env vars.
- **ApiToolkit.Discovery** - Macro module generating 8 discovery functions across multiple providers.

[0.1.0]: https://github.com/ZenHive/api_toolkit/releases/tag/v0.1.0
