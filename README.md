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
  {ApiToolkit.InboundLimiter, name: MyApp.IPLimiter, limit: {100, :minute}}
]
```

### Protect Endpoints with Inbound Rate Limiting

```elixir
case ApiToolkit.InboundLimiter.check(MyApp.IPLimiter, client_ip) do
  :ok -> handle_request(conn)
  {:rate_limited, retry_after_ms} ->
    conn
    |> put_resp_header("retry-after", to_string(div(retry_after_ms, 1000)))
    |> send_resp(429, "Too Many Requests")
end
```

Uses a sliding window approximation (same algorithm as Cloudflare/Nginx) to prevent burst-at-boundary issues. The `check/2` call is a direct ETS operation with no GenServer overhead.

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
| `ApiToolkit.Provider` | Behaviour + `defapi` macro for defining API providers |
| `ApiToolkit.Discovery` | Macro generating discovery functions across providers |

## Documentation

Full docs available at [HexDocs](https://hexdocs.pm/api_toolkit).

## License

MIT — see [LICENSE](LICENSE) for details.
