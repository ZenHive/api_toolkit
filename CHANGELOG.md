# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **ApiToolkit.MCP.Payment** — per-tool payment gating for MCP JSON-RPC transport, delegating the protocol to `MPP.Mcp` (mpp 0.14). api_toolkit contributes tier gating (only `:paid` tools are gated, fail-closed when a tool's tier is unknown), payment capability advertisement in the `initialize` response under `capabilities.experimental.payment`, and optional rejection recording via `ApiToolkit.Rejections`. MPP owns challenge generation, HMAC binding, JCS canonicalization, credential verification, replay protection, receipt attachment, and JSON-RPC error shaping: `-32042` (Payment Required), `-32602` (malformed credential), `-32043` (verification failed), each with RFC 9457 problem details in `error.data.problem`. Credentials are read from `params._meta["org.paymentauth/credential"]` or root message `_meta`; receipts land in `result._meta["org.paymentauth/receipt"]`. Zero-config via `use ApiToolkit.MCP, payment: [...]` — Plug auto-detects `payment_config/0` on the handler, and the full `MPP.Plug.init/1` option set (`:expires_in`, `:opaque`, `:digest`, `:intent`, `:methods`, `:store`) is available.

  **Replay protection is on by default** — a verified credential is single-use. The default dedup store is started by the `:mpp` application, so single-node deployments need no setup; multi-node deployments without sticky routing must configure a shared `:store` implementing atomic `check_and_mark/2`. A paid tool that raises or returns an error still consumes the credential and still receives its receipt: MPP claims the credential before invoking the tool, and withholding the receipt would leave the caller without proof of payment.

  `{:mpp, "~> 0.14"}` is an **optional** dependency — consumers using payment gating declare it themselves, so apps using only the cache/limiter modules don't pull the on-chain stack.

- **ApiToolkit.OpenAPI** — OpenAPI 3.1 document generator from Discovery metadata. `render/2` follows the same pattern as Homepage and LLMs (Discovery module + opts). Returns a JSON-serializable map. GET endpoints produce query `parameters`; POST endpoints produce `requestBody` with JSON schema. Optional `:pricing` function enables per-endpoint `x-payment-info` extensions and 402 responses. Optional `:categories` and `:docs` add `x-service-info` at document root. Additional info fields: `:description`, `:contact`, `:license`, `:url` (servers).

- **ApiToolkit.LLMs** — Markdown document generator for LLM consumption from Discovery metadata. `render/2` mirrors Homepage's API pattern (`:name`, `:version`, `:description`, `:url`, `:discovery_paths`, `:group_by`, `:group_labels`). Additionally supports `:pricing` — a user-provided function returning per-endpoint pricing text or nil. Renders full parameter documentation (type, required flag, description, examples), example GET request URLs, and a Discovery footer with horizontal rule separator.

- **ApiToolkit.Homepage** — Plain-text homepage generator from Discovery metadata. `render/2` takes a Discovery module and options (`:name`, `:version`, `:description`, `:url`, `:discovery_paths`). Configurable endpoint grouping via `:group_by` function — no hardcoded tier concept. Formats GET endpoints with example query strings from `defapi` param `:example` metadata. Designed for terminal and agent consumption.

- **Resource/prompt registration** — `use ApiToolkit.MCP` now accepts optional `:resources` and `:prompts` options for declarative MCP resource and prompt registration. Resources declare a `:read` function called at runtime; prompts declare a `:handler` function receiving arguments. The macro generates `resources/0`, `read_resource/1`, `prompts/0`, and `get_prompt/2` callbacks. Handler capability advertisement correctly gates on both listing AND operation callbacks being present.

- **ApiToolkit.MCP** — `use ApiToolkit.MCP` macro generates a complete `MCP.Server` implementation from Discovery metadata. Zero-boilerplate: provide `:discovery` module and `:server_info`, get `tools/0`, `server_info/0`, and `dispatch_map/0` for free.

- **ApiToolkit.MCP.ToolBuilder** — Pure-function module converting Provider/Discovery endpoints into MCP tool definitions. Path-based tool naming (`/api/hex/encode` → `hex_encode`), JSON Schema generation from Provider params, result translation (strips cache TTL, maps Provider errors to MCP format). Dispatch map links tool names to `{module, function, tier}` tuples — extensibility seam for T3 payment layer.

### Fixed

- **MCP.Payment**: Challenge IDs are now HMAC-bound the way every other MPP SDK binds them. The previous implementation, written against mpp 0.3 before MPP shipped an MCP transport, HMAC'd the raw JCS string where MPP binds `base64url(JCS(request))` — so its challenges could not be verified by mpp-rs, mppx, or `MPP.Client.MCP`. It also verified against the credential's *echoed* realm rather than the server's configured one, never bound `intent`, accepted challenges with no expiration, had no replay protection, and raised an uncaught `FunctionClauseError` (surfacing as a 500) on a request containing a float. Delegating to `MPP.Mcp` resolves all of these; `MPP.Verifier` additionally adds Tier-2 pinned-field checks and telemetry.

- **MCP.Handler**: A tool result's `_meta` is now a string key. It was an atom, which collided with the string `"_meta"` that receipt attachment writes, emitting `_meta` twice in the encoded JSON for a paid tool returning metadata.

- **Homepage**: `discovery_paths: []` no longer renders an empty "Discovery:" section, matching `ApiToolkit.LLMs`.

- **MCP.Payment**: A client-supplied `_meta` that isn't a JSON object (`"_meta": "x"`, `"_meta": []`) no longer crashes the transport. Credential extraction matches the map shape explicitly instead of using `get_in/2`, so malformed metadata reaches the JSON-RPC error path.

- **MCP.Payment**: Payment gating now fails closed. A tool is served for free only when the handler's `dispatch_map/0` lists it under a non-`:paid` tier; a handler that doesn't export `dispatch_map/0`, or that omits the tool, has it treated as paid. Previously any hand-written `MCP.Server` implementation with a payment config served every paid tool for free, silently. `dispatch_map/0` is now a declared optional callback on `ApiToolkit.MCP.Server`.

- **MCP.Plug**: Payment config is resolved per request instead of in `init/1`. Phoenix routers evaluate `init/1` at compile time, which baked the build machine's `%Payment.Config{}` — secret key included — into the router's BEAM, and silently disabled gating when the handler module wasn't compiled yet at router-compile time.

- **MCP**: `use ApiToolkit.MCP, payment: [capabilities: %{...}]` no longer raises `BadMapError` on the first `initialize` request. The user-supplied capabilities map was double-escaped and reached `capabilities/0` as an AST tuple.

- **MCP.Handler**: Exception safety for `resources/read` and `prompts/get`. Raising `:read` or `:handler` functions now produce MCP error responses instead of crashing the process. Matches existing `tools/call` exception-catching behavior.

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
