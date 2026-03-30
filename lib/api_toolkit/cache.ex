defmodule ApiToolkit.Cache do
  @moduledoc """
  ETS-based cache with TTL support.

  Stores values with expiration timestamps and periodically cleans up expired entries.

  ## Usage

  Add to your supervision tree:

      children = [
        ApiToolkit.Cache,
        # or with custom cleanup interval:
        {ApiToolkit.Cache, cleanup_interval_ms: 120_000}
      ]
  """
  use GenServer

  defstruct [:table]

  @type t :: %__MODULE__{table: :ets.table()}

  @table __MODULE__
  @default_cleanup_interval_ms 60_000

  # Client API

  @doc """
  Starts the cache GenServer and creates the ETS table.

  ## Options

  - `:cleanup_interval_ms` - How often to clean up expired entries (default: 60000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a cached value if it exists and hasn't expired.

  Returns `{:ok, value}` if found and valid, `:miss` if not found or expired.
  """
  @spec get(term()) :: {:ok, term()} | :miss
  def get(key) do
    now = System.system_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        {:ok, value}

      _ ->
        :miss
    end
  end

  @doc """
  Stores a value in the cache with the given TTL in milliseconds.
  """
  @spec put(term(), term(), pos_integer()) :: :ok
  def put(key, value, ttl_ms) do
    expires_at = System.system_time(:millisecond) + ttl_ms
    :ets.insert(@table, {key, value, expires_at})
    :ok
  end

  @doc """
  Deletes a specific cache entry by key.

  Returns `:ok` regardless of whether the key existed.
  """
  @spec delete(term()) :: :ok
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  @doc """
  Clears all entries from the cache.

  Returns the number of entries that were deleted.
  """
  @spec clear() :: non_neg_integer()
  def clear do
    count = :ets.info(@table, :size)
    :ets.delete_all_objects(@table)
    count
  end

  @doc """
  Lists all cache keys (for debugging/admin purposes).
  """
  @spec keys() :: [term()]
  def keys do
    :ets.foldl(fn {key, _value, _expires}, acc -> [key | acc] end, [], @table)
  end

  @doc """
  Returns cache statistics including entry count and memory usage.
  """
  @spec stats() :: %{entry_count: non_neg_integer(), memory_bytes: non_neg_integer()}
  def stats do
    %{
      entry_count: :ets.info(@table, :size),
      memory_bytes: :ets.info(@table, :memory) * :erlang.system_info(:wordsize)
    }
  end

  # Server callbacks

  @impl true
  def init(opts) do
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_cleanup(cleanup_interval_ms)
    {:ok, %{table: table, cleanup_interval_ms: cleanup_interval_ms}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{table: table}) do
    :ets.delete(table)
    :ok
  end

  # Private functions

  # Schedules the next periodic cleanup sweep
  defp schedule_cleanup(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  # Removes all entries whose expiration timestamp is in the past
  defp cleanup_expired do
    now = System.system_time(:millisecond)

    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])
  end
end
