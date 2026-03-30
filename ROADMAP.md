# ApiToolkit Roadmap

Reusable API infrastructure for Elixir services. Published on [Hex](https://hex.pm/packages/api_toolkit).

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

---

## 🎯 Current Focus

**Phase 3 — MCP Server Framework** — Build reusable MCP server infrastructure.

### ✅ Recently Completed
| Task | Description | Notes |
|------|-------------|-------|
| T1 | MCP JSON-RPC server | Behaviour + Handler + Plug, protocol 2025-03-26. Fixed: `_json` batch unwrapping, batched `initialize` rejection, empty body parse error, version negotiation per spec, capability/operation callback alignment, `Code.ensure_loaded` for handler modules |
| T7 | Proxy-aware remote IP plug | Configurable header, IPv4+IPv6 |
| T5 | Rejection tracking | Dynamic types, named instances |
| T6 | Rate limit plug | Configurable limiter, skip paths, optional rejections |
| T8 | Router helpers | handle_endpoint + merge_params with optional metrics |

---

## Phase 1 — Foundation ✅

> 6 modules shipped in v0.1.0. See [CHANGELOG.md](CHANGELOG.md#010---2026-03-30) for details.
> Built: Cache, RateLimiter, InboundLimiter, Metrics, Provider, Discovery.

## Phase 2 — Plug Infrastructure ✅

> 4 modules extracted from Strip0x as configurable building blocks. See [CHANGELOG.md](CHANGELOG.md#unreleased) for details.
> Built: Plug.RemoteIp, Rejections, Plug.RateLimit, Router.Helpers.

- ✅ **T5: Rejection tracking** [D:2/B:6/U:7 → Eff:3.25]
- ✅ **T6: Rate limit plug** [D:2/B:6/U:8 → Eff:3.5]
- ✅ **T7: Proxy-aware remote IP plug** [D:1/B:4/U:6 → Eff:5.0]
- ✅ **T8: Router helpers** [D:2/B:5/U:7 → Eff:3.0]

## Phase 3 — MCP Server Framework

Expose API endpoints as MCP tools so AI agents (Claude Code, Cursor, Windsurf) consume them natively. Full MCP protocol support with optional MPP payment layer for paid tools.

**Source references:** MPP library at `../mpp/` — `MPP.Plug`, `MPP.Challenge`, `MPP.Credential`, `MPP.Receipt`, `MPP.Method` behaviour. No MCP implementation exists yet in either project — T1/T2/T4 are net-new.

- ✅ **T1: MCP JSON-RPC server** [D:4/B:8/U:9 → Eff:2.13] 🎯

- ⬜ **T2: Tool registration DSL** [D:3/B:7/U:8 → Eff:2.5] 🎯
      Provide a `use ApiToolkit.MCP` macro or behaviour for registering MCP tools from Provider/Discovery metadata. Auto-converts `defapi` endpoint declarations into MCP tool definitions (name, description, inputSchema). Tool naming convention configurable (path-based default: `/api/hex/encode` → `hex_encode`). Dispatch map linking tool names to `{module, function, tier}` tuples.

- ⬜ **T3: MPP payment layer for MCP** [D:4/B:7/U:8 → Eff:1.88] 🚀
      Translate MPP's HTTP 402 challenge/credential/receipt flow to MCP JSON-RPC transport per the [MPP MCP transport binding spec](https://mpp.dev/protocol/transports/mcp). Error code `-32042` (Payment Required) with challenges in `error.data.challenges`. Error code `-32043` (Payment Verification Failed). Credentials in `params._meta["org.paymentauth/credential"]`, receipts in `result._meta["org.paymentauth/receipt"]`. Reuses `MPP.Plug.init/1` for config building to guarantee byte-identical HMAC binding. Advertises payment capabilities in `initialize` response under `capabilities.experimental.payment`. Records rejections for metrics integration.
      📂 `../mpp/lib/mpp/plug.ex` (HTTP 402 flow), `../mpp/lib/mpp/challenge.ex`, `../mpp/lib/mpp/credential.ex`, `../mpp/lib/mpp/receipt.ex`

- ⬜ **T4: Resource/prompt registration** [D:2/B:4/U:5 → Eff:2.25] 🎯
      Let consumers register MCP resources (e.g., OpenAPI spec, llms.txt, discovery metadata) and prompt templates via callback module. Resources support `resources/read` with URI-based lookup. Prompts support `prompts/get` with argument substitution.

## Phase 4 — Agent Discovery

Auto-generated documentation endpoints from Provider/Discovery metadata. Makes any api_toolkit service self-describing for AI agents.

**Source references:** All Phase 4 modules have running implementations in `../strip0x/` with tests. Pricing flows through `../mpp/`.

- ⬜ **T9: Per-endpoint pricing in Discovery** [D:3/B:6/U:8 → Eff:2.33] 🎯 *(depends on T3)*
      `ApiToolkit.Discovery` pricing enrichment — support per-endpoint/per-tier pricing declarations in `defapi` metadata. Flow pricing through Discovery → OpenAPI (`x-payment-info`) → LLMs → MCP challenges. Currently Strip0x uses uniform pricing for all paid endpoints; this enables tiered pricing (e.g., Basic $0.0001, Data $0.01, Compute $0.10) configurable per-endpoint or per-tier group. Pricing read at request time from app config (same runtime pattern as MPP).
      📂 `../strip0x/lib/strip0x/discovery.ex` (current uniform pricing), `../mpp/lib/mpp/plug.ex` (runtime config pattern)

- ⬜ **T10: OpenAPI 3.1 generation** [D:3/B:6/U:7 → Eff:2.17] 🎯
      `ApiToolkit.OpenAPI` — auto-generates OpenAPI 3.1 document from Provider/Discovery endpoint metadata. GET → query parameters, POST → requestBody with JSON schema. MPP `x-payment-info` extensions for paid endpoints (uses per-endpoint pricing from T9). `x-service-info` with docs URLs. Configurable server info, contact, license.
      📂 `../strip0x/lib/strip0x/openapi.ex` + `../strip0x/test/strip0x/openapi_test.exs`

- ⬜ **T11: llms.txt generation** [D:2/B:5/U:7 → Eff:3.0] 🎯 `[P]`
      `ApiToolkit.LLMs` — auto-generates LLM-readable plain-text API overview from Discovery metadata. Groups by tier (free/paid), includes parameter descriptions, example requests, pricing. Generic for any agent-facing API service.
      📂 `../strip0x/lib/strip0x/llms.ex` + `../strip0x/test/strip0x/llms_test.exs`

- ⬜ **T12: Plain-text homepage** [D:1/B:3/U:4 → Eff:3.5] 🎯 `[P]`
      `ApiToolkit.Homepage` — dynamic plain-text homepage from Discovery metadata. Lists all endpoints with examples, discovery URLs, version info. Configurable service name and description. Cache-Control header.
      📂 `../strip0x/lib/strip0x/homepage.ex` + `../strip0x/test/strip0x/homepage_test.exs`

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
