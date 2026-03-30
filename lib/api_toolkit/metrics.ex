defmodule ApiToolkit.Metrics do
  @moduledoc """
  Tracks request metrics for API endpoints.

  Records request counts, cache hit/miss rates, and response times.
  Uses ETS for fast concurrent writes.

  ## Usage

  Add to your supervision tree:

      children = [
        ApiToolkit.Metrics
      ]

  Then record metrics from your router:

      ApiToolkit.Metrics.record("/my/endpoint", :hit, duration_us)
  """
  use GenServer

  @table __MODULE__
  @precision_digits 3

  # Client API

  @doc """
  Starts the metrics GenServer and creates the ETS table.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a request metric.

  ## Parameters

  - `endpoint` - The endpoint path (e.g., "/brave/search")
  - `cache_status` - `:hit` or `:miss`
  - `duration_us` - Response time in microseconds
  """
  @spec record(String.t(), :hit | :miss, non_neg_integer()) :: :ok
  def record(endpoint, cache_status, duration_us) do
    now = System.system_time(:second)
    key = {endpoint, cache_status}

    # Atomic increment for count
    :ets.update_counter(@table, key, {2, 1}, {key, 0, 0, 0})

    # Update total duration and track min/max
    :ets.update_counter(@table, key, {3, duration_us}, {key, 0, 0, 0})

    # Track last request time
    :ets.update_element(@table, key, {4, now})

    :ok
  end

  @doc """
  Returns all metrics as a map.
  """
  @spec get_all() :: map()
  def get_all do
    (&reduce_raw_metrics/2)
    |> :ets.foldl(%{}, @table)
    |> Map.new(&format_endpoint_metrics/1)
  end

  @doc """
  Returns a summary of all metrics.
  """
  @spec summary() :: map()
  def summary do
    metrics = get_all()

    total_requests = metrics |> Map.values() |> Enum.map(& &1.total_requests) |> Enum.sum()
    total_hits = metrics |> Map.values() |> Enum.map(& &1.cache_hits) |> Enum.sum()
    total_misses = metrics |> Map.values() |> Enum.map(& &1.cache_misses) |> Enum.sum()

    %{
      total_requests: total_requests,
      total_cache_hits: total_hits,
      total_cache_misses: total_misses,
      overall_hit_rate: calculate_hit_rate(total_hits, total_requests),
      endpoints_count: map_size(metrics),
      by_endpoint: metrics
    }
  end

  @doc """
  Resets all metrics.
  """
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def terminate(_reason, _state) do
    :ets.delete(@table)
    :ok
  end

  # Private functions

  # Reduces raw ETS entries into accumulated endpoint data grouped by endpoint path
  defp reduce_raw_metrics({{endpoint, cache_status}, count, total_duration_us, last_request_at}, acc) do
    endpoint_data = Map.get(acc, endpoint, %{hits: 0, misses: 0, total_duration_us: 0})

    updated =
      case cache_status do
        :hit ->
          %{
            endpoint_data
            | hits: endpoint_data.hits + count,
              total_duration_us: endpoint_data.total_duration_us + total_duration_us
          }

        :miss ->
          %{
            endpoint_data
            | misses: endpoint_data.misses + count,
              total_duration_us: endpoint_data.total_duration_us + total_duration_us
          }
      end

    updated =
      Map.put(
        updated,
        :last_request_at,
        max(Map.get(endpoint_data, :last_request_at, 0), last_request_at)
      )

    Map.put(acc, endpoint, updated)
  end

  # Formats accumulated endpoint data into the final metrics structure
  defp format_endpoint_metrics({endpoint, data}) do
    total_requests = data.hits + data.misses

    {endpoint,
     %{
       total_requests: total_requests,
       cache_hits: data.hits,
       cache_misses: data.misses,
       hit_rate: calculate_hit_rate(data.hits, total_requests),
       avg_duration_us: if(total_requests > 0, do: div(data.total_duration_us, total_requests), else: 0),
       last_request_at: data.last_request_at
     }}
  end

  # Calculates hit rate as a ratio, returns 0.0 if no requests
  defp calculate_hit_rate(_hits, 0), do: 0.0
  defp calculate_hit_rate(hits, total), do: Float.round(hits / total, @precision_digits)
end
