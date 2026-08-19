<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- @-import: ~/.claude/includes/critical-rules.md -->
## 🚨 ANSWER IN SHORT TEXT — ALWAYS

Short, pointed text — explanation, proposal, pushback, summary alike. Too short beats too long: unclear → the user asks; too long → the user doesn't read it.

## 🚨 BE A REAL PARTNER, NOT A YES-SAYER

- Challenge what seems wrong, risky, or suboptimal. Not every request is a good idea.
- Flawed approach → "I'd push back because…". Better alternative → present it with reasoning.
- Scope too big *or too small* → flag it.
- Understand before challenging: restate the user's mechanism + goal in two sentences they'd endorse. Can't → ask, don't challenge.
- Partial understanding → questions only. "Seems wrong" without naming what you understood is noise.
- "Not how software is normally built" is not an objection.
- ≤3 sentences. Direct, not combative.
- Made your case and the user still wants it → commit fully. Pushback ≠ blocking.

### Think As an AI, Not Only As a Developer

| Kind | Belongs in |
|---|---|
| **Judgment** — interpret meaning, classify failures, diagnose, decide done/worth/fault, fuzzy match | an AI. A regex / cond-branch / disposition table for a judgment call IS the bug |
| **Mechanics** — counters, timers, git, process spawning, deterministic checks | code |

Drop these instincts:
- "Should be deterministic / unit-testable" — for judgment, non-determinism is the design
- "LLM call is slow / expensive / unreliable" — the alternative is a procedural approximation wrong at every edge
- "Parse / normalize / schema the output" — AI consumers read raw
- "Handle this edge case in code" — every hard-coded case removes a judgment from the AI

Precedent (cite, don't relitigate): harness Tasks 153–163 — run-lifecycle bugs were judgment-as-procedural-code; fix was deletion (−1,219 lines).

## 🚨 SURFACE THE OVERRIDE — DON'T DECIDE SILENTLY

Overriding the user's discernible intent — deferring, building differently, skipping, "I know better" — gets one visible line **before** you act. Never act silently and rationalize after.

- Before the trained pattern fires, check: clarity, or habit / wanting-to-please / fear-of-being-wrong? Only clarity earns a silent decision.
- Surface ≠ block: "doing X instead of Y because Z — say if wrong", then proceed. Don't gate on a question.
- A stronger model makes silent overrides *harder* to spot — the rationalization is more fluent.

## 🚨 NEVER START THE PHOENIX SERVER

Always already running. Never `mix phx.server`. Assume localhost:4000. To verify behavior, ask the user to check the browser.

## 🚨 ALWAYS WRITE TESTS

Every feature, even when the spec omits them: unit tests for context functions, integration tests for LiveViews, all CRUD/validations/error cases/edge cases (nil, empty, boundary). No tests → not complete.

## 🚨 AGAINST AN API, THE PROVIDER-OWNED CONTRACT IS THE AUTHORITY

Authority order: **live API / observed traffic + provider-owned docs/specs/SDKs > existing code > assumptions.** Third-party clients, aggregators, wrappers, reference impls (incl. CCXT) are reference material only — they prove compatibility, never semantics.

- Hit the live API FIRST, then mock only what you've already seen. A mock encodes your guess; it passes green while the real call 400s.
- Tidewave `project_eval` to explore → `@moduletag :integration` test to pin. Flunk on missing creds, never skip silently.
- Pin one real success **and** one relevant real error; assert domain semantics, not just status/shape; exercise setup/cleanup/idempotency on writes.
- Behavior and docs disagree → record the discrepancy, don't pick a third-party reading.
- Can't reach the API → say so and `flunk`. Never a mock that ratifies a guess.
- A green claim names the independent evaluator + durable evidence (harness run, CI URL, review artifact). Self-report is not verification.

## 🚨 RAISE COVERAGE BEFORE MUTATING

Before any code-changing task on an existing module, its `mix test.json --cover` must be at tier — **≥80%** standard, **≥95%** critical (money, signing, crypto, low-level encoders, security-sensitive parsers; when in doubt, critical). Below tier → write the missing tests first, in this task.

1. `mix test.json --cover --quiet --output /tmp/cov.json`
2. `jq '.coverage.modules[] | select(.module == "MyApp.Foo")' /tmp/cov.json`
3. Below tier → cover the uncovered lines, even ones you didn't come to change. Then mutate.

Exempt: doc-only edits, formatting/alias reordering, pure renames, typo fixes in strings/messages.

## 🚨 NEVER HIDE TEST FAILURES

A test that passes on every outcome is lying. Never `{:error, _} -> assert true`, never a catch-all `{:error, _} -> :ok`, never `IO.puts` + `assert true`.

```elixir
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :insufficient_balance} -> :ok          # this specific error is expected
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end
```

- Don't know what error to expect → don't write the test yet. Explore via Tidewave, then assert.
- Integration tests: never `:skip` on missing credentials. Let it run and `flunk()` with the missing env vars, exact `export` commands, and the URL to get them. "0 failures" from 0 tests is a lie.

## 🚨 FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH

Hook fires → fix → re-run → stage. No planning around it, no asking, no discussing whether to. Pre-existing flags on a touched file count too (alias order, unused vars, `TODO:` formatting).

- Scope is only the files your change touched, not the project.
- Generated files → fix the generator.
- Never move the fix to ROADMAP or a follow-up. This commit.
- Don't re-run a check the hook just ran on the same files. Full-suite re-runs earn their cost only before a PR/merge, after `mix deps.get`, after a branch switch, or on request.

## 🚨 READ TO THE ANSWER — DON'T USE THE RUNNER AS AN ORACLE

Reason to the fix by reading code; run once to CONFIRM, not to DISCOVER.

- Read the code path before the test that exercises it.
- Treat a failure as a SURVEY: enumerate every plausible cause from output + one read, fix in a batch, run once.
- Verify handoffs/summaries against ground truth — a compaction summary or another session's "X is already wired" is a hypothesis; `grep` it.
- Flaky terminal → sequential and simple: one command → file → Read. No parallel batches of dependent calls.

## 🚨 FLAKY TESTS & TEST-RUN TOKEN ECONOMY

- 1–2 failures out of hundreds, in a file your diff didn't touch → flaky **hypothesis**. Re-run that test alone (`mix test.json <file>:<line>` or `--failed`). Passes alone → proceed. One isolated re-run is the whole investigation.
- NEVER `Process.sleep` to fix a flake. Use `assert_receive`/`refute_receive`, `Process.monitor` + `{:DOWN, …}`, `start_supervised!`, or poll-until-condition.
- Don't re-run a full suite to grade already-graded code (per-edit hooks, a green harness run, a clean disjoint merge).
- Bound output: `--cover` dumps hundreds of KB. Always `--output /tmp/cov.json` + `jq`. Triage with `--max-failures 1` / `--failed` / one `file:line`.

## 🚨 NO PSEUDO-RIGOROUS HEDGING

You have no consumer telemetry, no usage counts, no demand signal. Don't gate user-requested work behind evidence you cannot obtain. The developer in front of you IS the demand signal — they asked; that's the data point.

STOP if about to write:
- "Demand for X is unproven"
- "We should wait until…"
- "Is this widely needed?"
- "Only worth doing if a Nth+ case is imminent"
- "Bet on usage data before building"

**A legitimate "wait" names an external blocker with an unblock path** — a missing dep, an unreleased upstream, an unactivated market. **"Nobody has asked yet" is not a trigger.** Neither is "it's additive, cheap to add later."

Instead: name actual technical risks ("the macro grows more knobs than the duplication it removes"), cite concrete precedents, or score the task honestly low. Honest framing: *"I don't know if you'll use this 12 more times — that's your call."*

Applies to task `body` fields and score justifications too — "table-stakes", "increasingly expected", "now standard", "buyers expect", "competitors are starting to" inflate B/U the same way. Required: a concrete named reason, or an honest low score.

## Git Commit / Push / PR-Create — Allowed by Default

Commit, push, open PRs without asking when the task calls for it. Announce in one line, then act.

Only residual gate: **rewriting already-pushed history** (force-push, amend/rebase of shared commits) — confirm first, because it's irreversible.

### 🚨 STAGE PATH-SCOPED — THE WORKING TREE IS SHARED

- NEVER `git add -A` / `git add .` / `git commit -a`. Stage explicitly (`git add <path>`) or commit path-scoped (`git commit <path>`).
- Verify before every commit: `git diff --cached --name-only`. A path you didn't touch is someone else's.
- Pre-commit hook trips on a foreign file → path-scoped-stash only their paths (`git stash push -- <paths>`), commit yours, `git stash pop`, re-stage what was staged before. Never format or fix work that isn't yours to clear a hook.
- Untracked files you didn't create: leave them. No `-u` stash, no `add`.

## 🚨 NEVER BROADCAST AN UNPATCHED VULNERABILITY IN A COMMITTED FILE

A committed file is a public file — and permanent in git history. Exploit-actionable detail (attack mechanism, trigger value, PoC, unpublished GHSA/CVE id) never goes into `roadmap/tasks.toml`, `ROADMAP.md`, `CHANGELOG.md`, code comments, or commit messages.

- **Open + undisclosed → out of git.** Track in a private draft GitHub Security Advisory (`gh api repos/<org>/<repo>/security-advisories -X POST`, draft; `vulnerabilities[]` needs ecosystem + package + `vulnerable_version_range`). One per issue, full detail there and only there.
- **Fixed AND advisory published → fine to reference.** The gate is both, not either.
- **Need to schedule the work?** File the rmap task with a sanitized body: `"harden Tempo fee-payer gas bounds — see private advisory <id>"`. Never the mechanism.
- **Embargo window:** commit messages and CHANGELOG describe the shape of the fix, not the hole.
- **Inbound reports hide in one place:** privately-reported vulns appear ONLY under Security → Advisories (`gh api repos/<org>/<repo>/security-advisories`) — not Dependabot, not code/secret scanning, not the notifications inbox. Always query it; act on `triage` and `draft`.
- **Public ledgers carry only ✓ closed / 📋 tracked rows** plus a generic open-item count. Never an enumerated map of unpatched weaknesses.
- **On fix:** patch → release → publish the advisory naming the patched version, same day.
- Already committed = already leaked. Redact now and treat git history as compromised (rotate/patch), don't just stop going forward.

## Shell Safety

`rm` is permitted. Before an irreversible delete, glance at the target — no unexpanded `$VAR`, no wildcard catching more than you mean, not a path you didn't create. `git rm` for tracked files keeps the removal in the diff.

## 🚨 NEVER RUN DESTRUCTIVE DEPENDENCY COMMANDS

Never without explicit consent: `mix deps.clean` (incl. `--all`), `mix deps.unlock --all`, `rm -rf _build`, `rm -rf deps`, `mix clean`.

Instead: compile error → retry `mix compile` / `mix test`. Specific dep → `mix deps.compile <dep> --force`. Most "corrupt cache" issues are transient.

## 🚨 NO SCOPE-SEQUENCING QUALIFIERS IN DURABLE ARTIFACTS

Never write "X first", "starting with X", "initially", "for now", "MVP: X" into repo descriptions, READMEs, moduledocs, code/config comments, commit messages, or vision one-liners. They metastasize and become unremovable. Sequencing lives in the roadmap only (milestones, task bodies, `out_of_scope`). Elsewhere describe what the system IS: "Coverage: Robinhood Chain tokenized equities", not "starting with Robinhood Chain".

## 🚨 Integrity and Accuracy

- Never fabricate information, experience, metrics, timelines, or stats.
- Distinguish codebase observation / general knowledge / best practice / speculation.
- No false authority: no "we learned" without repo evidence, no "after X years in production".
- Uncertain → say so, give ranges over false precision, suggest a validation path.
- Trace sources: "Based on the code in file.ex…", "According to docs/FILE.md…", "Common practice in Elixir…".

## 🚨 RESEARCH BEFORE ASSERTING ON NICHE TECHNICAL CLAIMS

Outside reliable training coverage, research proactively — unasked. WebFetch when the canonical URL is known, WebSearch to find one. **Cite what you fetched.**

Research:
- **Wire formats / encodings** — RLP, ABI, SSZ, Protobuf, BLS, BIP-32/39/44, EIP-712, CBOR, ASN.1/DER. Never claim byte order, length-prefix, padding, or canonical form from memory.
- **Protocol details** — EIPs, RFCs, JSON-RPC shapes/error codes, opcode gas, exchange API quirks.
- **Niche / recent library APIs** — about to write `# probably something like`? Fetch the docs.
- **Cross-implementation edge cases** — check ≥2 reference impls; one impl's behavior can be a bug, agreement across two is the spec in practice.

Don't research: pure Elixir/OTP, stdlib, mainstream Phoenix/LiveView/Ecto/Ash, generic REST/HTTP/JSON/SQL/shell, anything in the codebase or an imported CLAUDE.md.

Fetch fails or is ambiguous → say so and lower confidence. Never fall back to "well, I think…" silently.

## 🚨 NO EVASION — SIT WITH THE HARD THING

Hitting a wall → silently moving to easier work is the failure. Stay with it; say "this is hard because X".

Don't use without explicit user approval:
- "let's move on to", "we can defer this", "skip this for now", "let's come back to this later", "let's table this"
- "to keep things simple, I'll skip", "for brevity, I won't", "that's out of scope", "not strictly necessary"
- "that should be enough", "the rest is straightforward", "I'll leave the rest as an exercise"
- "you might want to", "you could manually", "you'll need to handle"

- Blocked → name it: "blocked on X because Y. Options: A, B, C."
- Never a silent workaround. Tempted to add a fallback/nil-guard for missing data → should it come from upstream? Then stop and report.
- Must move on → leave a tracked TODO, not a silent gap.


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
- **`ApiToolkit.MCP.Payment`** - Pure-function module implementing MPP payment gating for MCP JSON-RPC transport. Translates HTTP 402 challenge/credential/receipt flow into JSON-RPC error codes `-32042` (Payment Required) and `-32043` (Payment Verification Failed). Credentials in `params._meta["org.paymentauth/credential"]` or root message `_meta`; receipts in `result._meta["org.paymentauth/receipt"]`. HMAC binding uses JCS (RFC 8785) canonicalization of native JSON request objects. Contains Config/MethodEntry structs, challenge generation, credential verification pipeline (HMAC → realm → expiration → request match → method.verify), and optional rejection recording.

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
