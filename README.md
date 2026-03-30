# ApiToolkit

Reusable infrastructure for building API proxy/cache services in Elixir.

## Installation

Add `api_toolkit` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:api_toolkit, "~> 0.1.0"}
  ]
end
```

## Usage

### Define a Provider

```elixir
defmodule MyApp.Providers.Brave do
  use ApiToolkit.Provider,
    name: "Brave Search",
    description: "Web search via Brave API",
    rate_limit: "1 req/sec",
    cache_ttl_ms: 300_000

  defapi :search,
    path: "/brave/search",
    description: "Search the web",
    params: [
      %{name: "q", type: :string, required: true, description: "Search query"}
    ],
    errors: [:invalid_params, :rate_limited, :upstream_error],
    categories: [:web]

  def search(%{"q" => q}) when byte_size(q) > 0 do
    # call upstream API...
    {:ok, %{results: results}, 300_000}
  end
end
```

### Aggregate with Discovery

```elixir
defmodule MyApp.Discovery do
  use ApiToolkit.Discovery,
    providers: [
      MyApp.Providers.Brave,
      MyApp.Providers.Weather
    ]
end
```

This generates functions like `all_endpoints/0`, `search/1`, `describe/1`, `help/0`, `by_provider/0`, `categories/0`, and `by_category/1`.

### Add Infrastructure to Your Supervision Tree

```elixir
children = [
  ApiToolkit.Cache,
  ApiToolkit.Metrics,
  {ApiToolkit.RateLimiter, name: MyApp.RateLimiter.Brave, rate: {1, :second}},
  {ApiToolkit.RateLimiter, name: MyApp.RateLimiter.Weather, rate: {25, :day}},
  {ApiToolkit.InboundLimiter, name: MyApp.IPLimiter, limit: {100, :minute}},
  ApiToolkit.Rejections
]
```

### Plug Pipeline

```elixir
defmodule MyApp.Router do
  use Plug.Router

  # Rewrite conn.remote_ip from proxy header (Fly.io, Cloudflare, Nginx)
  plug ApiToolkit.Plug.RemoteIp
  # or: plug ApiToolkit.Plug.RemoteIp, header: "cf-connecting-ip"

  # Per-IP rate limiting with 429 + Retry-After
  plug ApiToolkit.Plug.RateLimit,
    limiter: MyApp.IPLimiter,
    rejections: ApiToolkit.Rejections

  plug :match
  plug :dispatch

  get "/api/search" do
    ApiToolkit.Router.Helpers.handle_endpoint(conn, MyApp.Search, :search)
  end
end
```

`Plug.RemoteIp` ensures downstream rate limiting sees the real client IP. `Plug.RateLimit` wraps `InboundLimiter` with proper HTTP 429 responses. `Router.Helpers` dispatches to endpoint functions with JSON responses and optional metrics.

### Runtime Configuration

Cache TTL can be overridden per-provider via environment variables:

```bash
BRAVE_CACHE_TTL_MS=600000  # Override default TTL for Brave provider
```

The env var name is derived from the last segment of the provider module name, uppercased.

## Modules

| Module | Description |
|--------|-------------|
| `ApiToolkit.Cache` | ETS-based cache with TTL and periodic cleanup |
| `ApiToolkit.RateLimiter` | Token bucket rate limiter for outbound throttling |
| `ApiToolkit.InboundLimiter` | Per-key rate limiter with sliding window for inbound protection |
| `ApiToolkit.Metrics` | Concurrent request metrics (counts, hit rates, durations) |
| `ApiToolkit.Rejections` | ETS-backed rejection counter by type and path |
| `ApiToolkit.Provider` | Behaviour + `defapi` macro for defining API providers |
| `ApiToolkit.Discovery` | Macro generating discovery functions across providers |
| `ApiToolkit.Plug.RemoteIp` | Rewrites `conn.remote_ip` from proxy header |
| `ApiToolkit.Plug.RateLimit` | Per-IP rate limiting plug with 429 + Retry-After |
| `ApiToolkit.Router.Helpers` | Endpoint dispatch with JSON responses and metrics |

## Documentation

Full docs available at [HexDocs](https://hexdocs.pm/api_toolkit).

## License

MIT — see [LICENSE](LICENSE) for details.
