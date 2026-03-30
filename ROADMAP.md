# ApiToolkit Roadmap

Reusable API infrastructure for Elixir services. Published on [Hex](https://hex.pm/packages/api_toolkit).

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

---

## 🎯 Current Focus

**Phase 2 — Plug Infrastructure** — Extract proven Plug modules from Strip0x. High-efficiency, independent tasks.

---

## Phase 1 — Foundation ✅

> 6 modules shipped in v0.1.0. See [CHANGELOG.md](CHANGELOG.md#010---2026-03-30) for details.
> Built: Cache, RateLimiter, InboundLimiter, Metrics, Provider, Discovery.

## Phase 2 — Plug Infrastructure

Reusable Plug modules extracted from Strip0x. Every Plug.Router API service rewrites these — provide them as configurable building blocks. High-efficiency proven extractions.

- ⬜ **T5: Rejection tracking** [D:2/B:6/U:7 → Eff:3.25] 🎯 `[P]`
      `ApiToolkit.Rejections` — ETS-backed GenServer tracking rejection counts by type and path. Same atomic-write pattern as `Metrics`. Configurable rejection types (e.g., `:rate_limited`, `:payment_required`, `:unauthorized`). Foldable into Metrics summary for a single `/metrics` endpoint. Extracted from `Strip0x.Rejections`.

- ⬜ **T6: Rate limit plug** [D:2/B:6/U:8 → Eff:3.5] 🎯 `[P]`
      `ApiToolkit.Plug.RateLimit` — configurable Plug wrapping `InboundLimiter`. Returns 429 + `Retry-After` header + JSON error body. Configurable: limiter name, skip paths (e.g., `/health`), response format. Optionally records rejections via `Rejections` module. Extracted from `Strip0x.Plug.RateLimit`.

- ⬜ **T7: Proxy-aware remote IP plug** [D:1/B:4/U:6 → Eff:5.0] 🎯 `[P]`
      `ApiToolkit.Plug.RemoteIp` — rewrites `conn.remote_ip` from a trusted proxy header. Configurable header name (default `Fly-Client-IP`, also `CF-Connecting-IP`, `X-Real-IP`). Validates with `:inet.parse_address/1`, no-op on failure. IPv4 + IPv6. Simpler than `remote_ip` package — single trusted header, no chain parsing. Extracted from `Strip0x.Plug.RemoteIp`.

- ⬜ **T8: Router helpers** [D:2/B:5/U:7 → Eff:3.0] 🎯 `[P]`
      `ApiToolkit.Router.Helpers` — reusable Plug.Router utilities: `handle_endpoint/3` (dispatch to `module.function(params)` + JSON response + metrics recording + timing), `merge_params/1` (query + body merge, body wins). Configurable JSON encoder (default `JSON`), metrics module. Extracted from `Strip0x.Router.Helpers`.

## Phase 3 — MCP Server Framework

Expose API endpoints as MCP tools so AI agents (Claude Code, Cursor, Windsurf) consume them natively. Full MCP protocol support with optional MPP payment layer for paid tools.

- ⬜ **T1: MCP JSON-RPC server** [D:4/B:8/U:9 → Eff:2.13] 🎯
      Reusable MCP server module handling the full JSON-RPC 2.0 protocol surface: `initialize` (with version negotiation), `tools/list`, `tools/call` (with safe exception catching), `resources/list`, `resources/read`, `prompts/list`, `prompts/get`, `ping`, notifications (`initialized`, `cancelled`). HTTP transport via Plug router. Follows Tidewave's proven pattern but generic — consumers register tools via callback module, not hardcoded. Uses Elixir built-in `JSON` module (not Jason). Protocol version: `2025-03-26`.

- ⬜ **T2: Tool registration DSL** [D:3/B:7/U:8 → Eff:2.5] 🎯
      Provide a `use ApiToolkit.MCP` macro or behaviour for registering MCP tools from Provider/Discovery metadata. Auto-converts `defapi` endpoint declarations into MCP tool definitions (name, description, inputSchema). Tool naming convention configurable (path-based default: `/api/hex/encode` → `hex_encode`). Dispatch map linking tool names to `{module, function, tier}` tuples.

- ⬜ **T3: MPP payment layer for MCP** [D:4/B:7/U:8 → Eff:1.88] 🚀
      Translate MPP's HTTP 402 challenge/credential/receipt flow to MCP JSON-RPC transport per the [MPP MCP transport binding spec](https://mpp.dev/protocol/transports/mcp). Error code `-32042` (Payment Required) with challenges in `error.data.challenges`. Error code `-32043` (Payment Verification Failed). Credentials in `params._meta["org.paymentauth/credential"]`, receipts in `result._meta["org.paymentauth/receipt"]`. Reuses `MPP.Plug.init/1` for config building to guarantee byte-identical HMAC binding. Advertises payment capabilities in `initialize` response under `capabilities.experimental.payment`. Records rejections for metrics integration.

- ⬜ **T4: Resource/prompt registration** [D:2/B:4/U:5 → Eff:2.25] 🎯
      Let consumers register MCP resources (e.g., OpenAPI spec, llms.txt, discovery metadata) and prompt templates via callback module. Resources support `resources/read` with URI-based lookup. Prompts support `prompts/get` with argument substitution.

## Phase 4 — Agent Discovery

Auto-generated documentation endpoints from Provider/Discovery metadata. Makes any api_toolkit service self-describing for AI agents.

- ⬜ **T9: Per-endpoint pricing in Discovery** [D:3/B:6/U:8 → Eff:2.33] 🎯 *(depends on T3)*
      `ApiToolkit.Discovery` pricing enrichment — support per-endpoint/per-tier pricing declarations in `defapi` metadata. Flow pricing through Discovery → OpenAPI (`x-payment-info`) → LLMs → MCP challenges. Currently Strip0x uses uniform pricing for all paid endpoints; this enables tiered pricing (e.g., Basic $0.0001, Data $0.01, Compute $0.10) configurable per-endpoint or per-tier group. Pricing read at request time from app config (same runtime pattern as MPP). Extracted from Strip0x T21.

- ⬜ **T10: OpenAPI 3.1 generation** [D:3/B:6/U:7 → Eff:2.17] 🎯
      `ApiToolkit.OpenAPI` — auto-generates OpenAPI 3.1 document from Provider/Discovery endpoint metadata. GET → query parameters, POST → requestBody with JSON schema. MPP `x-payment-info` extensions for paid endpoints (uses per-endpoint pricing from T9). `x-service-info` with docs URLs. Configurable server info, contact, license. Extracted from `Strip0x.OpenAPI`.

- ⬜ **T11: llms.txt generation** [D:2/B:5/U:7 → Eff:3.0] 🎯 `[P]`
      `ApiToolkit.LLMs` — auto-generates LLM-readable plain-text API overview from Discovery metadata. Groups by tier (free/paid), includes parameter descriptions, example requests, pricing. Generic for any agent-facing API service. Extracted from `Strip0x.LLMs`.

- ⬜ **T12: Plain-text homepage** [D:1/B:3/U:4 → Eff:3.5] 🎯 `[P]`
      `ApiToolkit.Homepage` — dynamic plain-text homepage from Discovery metadata. Lists all endpoints with examples, discovery URLs, version info. Configurable service name and description. Cache-Control header. Extracted from `Strip0x.Homepage`.

## Phase 5 — Ideas

- ⬜ **T13: Streamable HTTP transport (SSE)** [D:3/B:4/U:4 → Eff:1.33] 📋
      Add Server-Sent Events support alongside current POST-only MCP transport. Enables long-running tool calls with progress streaming.

- ⬜ **T14: Tool change notifications** [D:2/B:3/U:3 → Eff:1.5] 🚀
      Support `tools/listChanged` capability — notify connected clients when tool definitions change at runtime (e.g., new provider registered, endpoint added dynamically).

---

## Status Markers

- ⬜ Not started
- 🔄 In progress (include branch name)
- ✅ Done
- 🔶 Blocked
- `[P]` Independent — can parallelize

## D/B/U Scoring

- **D** (Difficulty): 1-10
- **B** (Benefit): 1-10
- **U** (Usefulness/Unlock): 1-10
- **Eff** = (B + U) / (2 × D) — higher is better
- Eff > 2.0: 🎯 | 1.5-2.0: 🚀 | 1.0-1.5: 📋 | < 1.0: ⚠️
