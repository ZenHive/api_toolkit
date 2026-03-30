# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

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
