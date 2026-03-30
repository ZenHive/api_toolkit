defmodule ApiToolkit.CacheTest do
  use ExUnit.Case, async: false

  alias ApiToolkit.Cache

  setup do
    start_supervised!(Cache)
    {:ok, test_id: System.unique_integer([:positive])}
  end

  describe "get/1 and put/3" do
    test "returns :miss for non-existent key", %{test_id: id} do
      assert Cache.get({:nonexistent, id}) == :miss
    end

    test "stores and retrieves a value", %{test_id: id} do
      Cache.put({:key1, id}, %{data: "test"}, 60_000)
      assert {:ok, %{data: "test"}} = Cache.get({:key1, id})
    end

    test "returns :miss for expired entries", %{test_id: id} do
      Cache.put({:expired_key, id}, "value", 1)
      Process.sleep(5)
      assert Cache.get({:expired_key, id}) == :miss
    end

    test "stores complex keys", %{test_id: id} do
      key = {:some_module, :search, %{"q" => "test"}, id}
      Cache.put(key, %{results: []}, 60_000)
      assert {:ok, %{results: []}} = Cache.get(key)
    end
  end

  describe "stats/0" do
    test "returns entry_count and memory_bytes" do
      stats = Cache.stats()

      assert is_integer(stats.entry_count)
      assert stats.entry_count >= 0
      assert is_integer(stats.memory_bytes)
      assert stats.memory_bytes > 0
      refute Map.has_key?(stats, :entries_by_provider)
    end

    test "entry_count increments after put/3", %{test_id: id} do
      initial_count = Cache.stats().entry_count

      Cache.put({:stats_test, id}, %{data: "test"}, 60_000)

      assert Cache.stats().entry_count == initial_count + 1
    end
  end

  describe "delete/1" do
    test "removes a specific cache entry", %{test_id: id} do
      key = {:delete_test, id}
      Cache.put(key, "value", 60_000)
      assert {:ok, "value"} = Cache.get(key)

      assert :ok = Cache.delete(key)
      assert Cache.get(key) == :miss
    end

    test "returns :ok even for non-existent key", %{test_id: id} do
      assert :ok = Cache.delete({:nonexistent_delete, id})
    end
  end

  describe "clear/0" do
    test "removes all entries and returns count" do
      Cache.put({:clear_test_1, :a}, "v1", 60_000)
      Cache.put({:clear_test_2, :b}, "v2", 60_000)
      initial_count = Cache.stats().entry_count
      assert initial_count >= 2

      deleted = Cache.clear()
      assert deleted == initial_count
      assert Cache.stats().entry_count == 0
    end
  end

  describe "keys/0" do
    test "returns list of all cache keys", %{test_id: id} do
      key1 = {:keys_test_1, id}
      key2 = {:keys_test_2, id}
      Cache.put(key1, "v1", 60_000)
      Cache.put(key2, "v2", 60_000)

      keys = Cache.keys()
      assert is_list(keys)
      assert key1 in keys
      assert key2 in keys
    end
  end

  describe "configurable cleanup interval" do
    test "accepts cleanup_interval_ms option" do
      # Stop the default one from setup
      stop_supervised!(Cache)

      # Start with custom interval - should not crash
      start_supervised!({Cache, cleanup_interval_ms: 100})

      Cache.put(:cleanup_test, "value", 60_000)
      assert {:ok, "value"} = Cache.get(:cleanup_test)
    end
  end
end
