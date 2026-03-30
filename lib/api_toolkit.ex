defmodule ApiToolkit do
  @moduledoc """
  Reusable infrastructure for building API proxy/cache services.

  Provides generic, composable modules for caching, rate limiting,
  metrics, provider definition, and endpoint discovery.

  ## Modules

  - `ApiToolkit.Cache` - ETS-based cache with TTL and periodic cleanup
  - `ApiToolkit.RateLimiter` - Token bucket rate limiter GenServer (outbound throttling)
  - `ApiToolkit.InboundLimiter` - Per-key rate limiter with sliding window (inbound protection)
  - `ApiToolkit.Metrics` - ETS-backed request metrics tracking
  - `ApiToolkit.Provider` - Behaviour and macros for defining API providers
  - `ApiToolkit.Discovery` - Macro for generating endpoint discovery functions
  """

  use Descripex.Discoverable,
    modules: [
      ApiToolkit.Cache,
      ApiToolkit.RateLimiter,
      ApiToolkit.InboundLimiter,
      ApiToolkit.Metrics
    ]
end
