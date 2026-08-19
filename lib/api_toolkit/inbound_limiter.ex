defmodule ApiToolkit.InboundLimiter do
  @moduledoc """
  Per-key inbound rate limiter using ETS with sliding window approximation.

  Designed for protecting API endpoints from excessive requests per client
  (IP address, API key, or any term). Unlike `ApiToolkit.RateLimiter` which
  blocks callers until tokens refill (outbound throttling), this module returns
  an immediate `:ok | {:rate_limited, retry_after_ms}` decision suitable for
  returning HTTP 429 responses.

  ## Usage

  Add to your supervision tree:

      children = [
        {ApiToolkit.InboundLimiter, name: MyApp.IPLimiter, limit: {100, :minute}},
        {ApiToolkit.InboundLimiter, name: MyApp.APIKeyLimiter, limit: {1000, :day}}
      ]

  Then check before processing requests:

      case ApiToolkit.InboundLimiter.check(MyApp.IPLimiter, client_ip) do
        :ok -> handle_request(conn)
        {:rate_limited, retry_after_ms} ->
          conn
          |> put_resp_header("retry-after", to_string(div(retry_after_ms, 1000)))
          |> send_resp(429, "Too Many Requests")
      end

  ## Algorithm

  Uses a sliding window approximation to avoid the burst-at-boundary problem
  of fixed windows. The weighted count is:

      weighted = prev_window_count * (1.0 - elapsed_fraction) + current_window_count

  This is the same algorithm used by Cloudflare and Nginx for rate limiting.

  ## Performance

  The `check/2` hot path is a direct ETS operation — no GenServer call.
  Config is stored in `:persistent_term` for zero-cost reads. The GenServer
  only handles periodic cleanup of stale entries.

  ## Multi-node Deployment

  This limiter is per-node only. In multi-node deploys, each node maintains
  independent counters. Effective limit in worst case is `N x configured_limit`
  where N is the number of nodes.

  **Fly.io specifics:** Routing is proximity-based and load-aware, but NOT sticky
  per client IP by default. `fly-replay` supports sticky sessions via cookies or
  authorization headers (not IP hash). If you configure cookie-based sticky sessions,
  per-node limiting becomes effectively global for that client.

  For abuse prevention without sticky sessions, per-node limiting is generally
  acceptable. For strict global rate limiting, use an external store (Redis).

  ## Options

  - `:name` - Required. The GenServer/ETS table name (atom)
  - `:limit` - Required. `{count, period}` where period is `:second | :minute | :day`
  - `:cleanup_interval_ms` - Optional. How often to purge stale entries (default: 60000)
  """
  use GenServer
  use Descripex, namespace: "/inbound-limiter"

  alias ApiToolkit.Internal.ChildSpec

  defstruct [:table, :window_size_ms, :cleanup_interval_ms]

  @type t :: %__MODULE__{
          table: atom(),
          window_size_ms: pos_integer(),
          cleanup_interval_ms: pos_integer()
        }

  # Client API

  @type check_result :: :ok | {:rate_limited, retry_after_ms :: pos_integer()}
  @type key :: term()

  @default_cleanup_interval_ms 60_000

  @doc """
  Returns a child specification for supervision.

  Uses the `:name` option as the unique child id.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    ChildSpec.build(__MODULE__, Keyword.fetch!(opts, :name), opts)
  end

  @doc """
  Starts an inbound limiter with the given name and limit configuration.

  ## Options

  - `:name` - Required. The GenServer name (atom), also used as the ETS table name
  - `:limit` - Required. Tuple of `{count, period}` where period is `:second`, `:minute`, or `:day`
  - `:cleanup_interval_ms` - Optional. How often to purge stale entries (default: 60000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  api(
    :check,
    "Check if a request for the given key is allowed under the rate limit. Direct ETS operation, sub-microsecond latency.",
    params: [
      server: [kind: :config, description: "The inbound limiter name"],
      key: [kind: :value, description: "Client identifier (IP, API key, or any term)"]
    ],
    returns: %{
      type: ":ok | {:rate_limited, pos_integer()}",
      description: ":ok if allowed, or {:rate_limited, retry_after_ms} if limit exceeded"
    }
  )

  @spec check(atom(), key()) :: check_result()
  def check(server, key) do
    {window_size_ms, limit} = :persistent_term.get({server, :config})
    now_ms = System.system_time(:millisecond)
    current_wid = div(now_ms, window_size_ms)
    elapsed_ms = rem(now_ms, window_size_ms)
    elapsed_fraction = elapsed_ms / window_size_ms

    case :ets.lookup(server, key) do
      [] ->
        :ets.insert_new(server, {key, 1, current_wid, 0, current_wid - 1})
        :ok

      [{^key, count, ^current_wid, prev_count, prev_wid}] ->
        prev = if prev_wid == current_wid - 1, do: prev_count, else: 0
        weighted = prev * (1.0 - elapsed_fraction) + (count + 1)

        if weighted > limit do
          retry_after = window_size_ms - elapsed_ms
          {:rate_limited, max(1, retry_after)}
        else
          :ets.update_counter(server, key, {2, 1})
          :ok
        end

      [{^key, count, wid, _prev_count, _prev_wid}] when wid == current_wid - 1 ->
        weighted = count * (1.0 - elapsed_fraction) + 1

        if weighted > limit do
          retry_after = window_size_ms - elapsed_ms
          {:rate_limited, max(1, retry_after)}
        else
          :ets.insert(server, {key, 1, current_wid, count, wid})
          :ok
        end

      [{^key, _count, _old_wid, _prev_count, _prev_wid}] ->
        :ets.insert(server, {key, 1, current_wid, 0, current_wid - 1})
        :ok
    end
  end

  api(:status, "Return the current estimated weighted count for a key without incrementing.",
    params: [
      server: [kind: :config, description: "The inbound limiter name"],
      key: [kind: :value, description: "Client identifier to check"]
    ],
    returns: %{type: "{:ok, float()} | :not_found", description: "Weighted count or :not_found"}
  )

  @spec status(atom(), key()) :: {:ok, float()} | :not_found
  def status(server, key) do
    {window_size_ms, _limit} = :persistent_term.get({server, :config})
    now_ms = System.system_time(:millisecond)
    current_wid = div(now_ms, window_size_ms)
    elapsed_fraction = rem(now_ms, window_size_ms) / window_size_ms

    case :ets.lookup(server, key) do
      [{^key, count, ^current_wid, prev_count, prev_wid}] ->
        prev = if prev_wid == current_wid - 1, do: prev_count, else: 0
        {:ok, prev * (1.0 - elapsed_fraction) + count}

      [{^key, count, wid, _prev_count, _prev_wid}] when wid == current_wid - 1 ->
        {:ok, count * (1.0 - elapsed_fraction)}

      # Server callbacks
      _ ->
        :not_found
    end
  end

  api(:reset, "Reset the counter for a specific key.",
    params: [
      server: [kind: :config, description: "The inbound limiter name"],
      key: [kind: :value, description: "Client identifier to reset"]
    ],
    returns: %{type: :ok, description: "Always returns :ok regardless of whether the key existed"}
  )

  @spec reset(atom(), key()) :: :ok
  def reset(server, key) do
    :ets.delete(server, key)
    :ok
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    {count, period} = Keyword.fetch!(opts, :limit)
    window_size_ms = period_to_ms(period)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    table = :ets.new(name, [:named_table, :public, :set, write_concurrency: true, read_concurrency: true])

    :persistent_term.put({name, :config}, {window_size_ms, count})

    schedule_cleanup(cleanup_interval_ms)

    {:ok, %__MODULE__{table: table, window_size_ms: window_size_ms, cleanup_interval_ms: cleanup_interval_ms}}
  end

  @impl true
  def handle_info(:cleanup, %__MODULE__{} = state) do
    cleanup_stale(state.table, state.window_size_ms)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    :persistent_term.erase({state.table, :config})
    :ets.delete(state.table)
    :ok
  end

  # Private functions

  # Schedules the next cleanup sweep
  defp schedule_cleanup(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  # Removes entries not seen in 2+ windows
  defp cleanup_stale(table, window_size_ms) do
    now_ms = System.system_time(:millisecond)
    stale_threshold = div(now_ms, window_size_ms) - 2

    :ets.select_delete(table, [
      {{:_, :_, :"$1", :_, :_}, [{:<, :"$1", stale_threshold}], [true]}
    ])
  end

  defp period_to_ms(:second), do: 1_000
  defp period_to_ms(:minute), do: 60_000
  defp period_to_ms(:day), do: 86_400_000
end
