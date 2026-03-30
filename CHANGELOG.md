# Changelog

All notable changes to this project will be documented in this file.

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
