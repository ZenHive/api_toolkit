defmodule ApiToolkit.InboundLimiterTest do
  use ExUnit.Case, async: true

  alias ApiToolkit.InboundLimiter

  # Each test uses a unique name to avoid collisions in async mode
  defp unique_name(test_name) do
    :"inbound_limiter_#{test_name}_#{System.unique_integer([:positive])}"
  end

  defp start_limiter(name, opts \\ []) do
    limit = Keyword.get(opts, :limit, {5, :second})
    cleanup = Keyword.get(opts, :cleanup_interval_ms, 60_000)

    start_supervised!({InboundLimiter, name: name, limit: limit, cleanup_interval_ms: cleanup})
  end

  # Sleeps until target_ms into the next window boundary.
  # Windows align to epoch time, so we compute the exact sleep needed.
  defp sleep_to_next_window(window_size_ms, target_offset_ms) do
    now = System.system_time(:millisecond)
    next_boundary = (div(now, window_size_ms) + 1) * window_size_ms
    sleep_ms = next_boundary - now + target_offset_ms
    Process.sleep(sleep_ms)
  end

  describe "check/2" do
    test "allows requests under limit" do
      name = unique_name(:under_limit)
      start_limiter(name, limit: {5, :second})

      for _ <- 1..5 do
        assert :ok = InboundLimiter.check(name, "192.168.1.1")
      end
    end

    test "rejects request over limit" do
      name = unique_name(:over_limit)
      start_limiter(name, limit: {3, :second})

      for _ <- 1..3 do
        assert :ok = InboundLimiter.check(name, "192.168.1.1")
      end

      assert {:rate_limited, retry_after} = InboundLimiter.check(name, "192.168.1.1")
      assert is_integer(retry_after)
      assert retry_after > 0
      assert retry_after <= 1_000
    end

    test "retry_after_ms is positive and bounded by window size" do
      name = unique_name(:retry_after)
      start_limiter(name, limit: {1, :second})

      assert :ok = InboundLimiter.check(name, "key")
      assert {:rate_limited, retry_after} = InboundLimiter.check(name, "key")
      assert retry_after >= 1
      assert retry_after <= 1_000
    end

    test "resets after window passes" do
      name = unique_name(:window_reset)
      start_limiter(name, limit: {2, :second})

      assert :ok = InboundLimiter.check(name, "key")
      assert :ok = InboundLimiter.check(name, "key")
      assert {:rate_limited, _} = InboundLimiter.check(name, "key")

      Process.sleep(1_100)

      assert :ok = InboundLimiter.check(name, "key")
    end

    test "sliding window reduces burst at boundary" do
      name = unique_name(:sliding_window)
      # 10 requests per second
      start_limiter(name, limit: {10, :second})

      # Fill the current window with 9 requests (just under limit)
      for _ <- 1..9 do
        assert :ok = InboundLimiter.check(name, "key")
      end

      # Sleep to ~500ms into the NEXT window boundary (epoch-aligned).
      # Previous window's 9 requests weighted at ~50% = ~4.5
      # So new window should allow roughly 5 more (4.5 + 5 = 9.5 < 10)
      # but NOT all 10 (4.5 + 10 = 14.5 > 10)
      sleep_to_next_window(1_000, 500)

      # Should be able to make some requests but not 10
      results =
        for _ <- 1..10 do
          InboundLimiter.check(name, "key")
        end

      ok_count = Enum.count(results, &(&1 == :ok))
      limited_count = Enum.count(results, &match?({:rate_limited, _}, &1))

      # With ~50% weight from prev window (9 * 0.5 = 4.5), should allow ~5
      # Allow tolerance for timing jitter: between 3 and 7
      assert ok_count >= 3, "Expected at least 3 allowed, got #{ok_count}"
      assert ok_count <= 7, "Expected at most 7 allowed, got #{ok_count}"
      assert limited_count > 0, "Expected some requests to be rate limited"
    end

    test "independent keys do not interfere" do
      name = unique_name(:independent_keys)
      start_limiter(name, limit: {2, :second})

      assert :ok = InboundLimiter.check(name, "ip_a")
      assert :ok = InboundLimiter.check(name, "ip_a")
      assert {:rate_limited, _} = InboundLimiter.check(name, "ip_a")

      # Different key still works
      assert :ok = InboundLimiter.check(name, "ip_b")
      assert :ok = InboundLimiter.check(name, "ip_b")
    end

    test "first request for new key always succeeds" do
      name = unique_name(:first_request)
      start_limiter(name, limit: {1, :second})

      assert :ok = InboundLimiter.check(name, "brand_new_key")
    end

    test "works with non-string keys" do
      name = unique_name(:non_string_keys)
      start_limiter(name, limit: {2, :second})

      assert :ok = InboundLimiter.check(name, {:ip, {192, 168, 1, 1}})
      assert :ok = InboundLimiter.check(name, {:ip, {192, 168, 1, 1}})
      assert {:rate_limited, _} = InboundLimiter.check(name, {:ip, {192, 168, 1, 1}})
    end
  end

  describe "status/2" do
    test "returns weighted count for active key" do
      name = unique_name(:status_active)
      start_limiter(name, limit: {10, :second})

      InboundLimiter.check(name, "key")
      InboundLimiter.check(name, "key")
      InboundLimiter.check(name, "key")

      assert {:ok, count} = InboundLimiter.status(name, "key")
      assert is_float(count)
      # Should be approximately 3.0 (exact value depends on elapsed time within window)
      assert count >= 2.5
      assert count <= 3.5
    end

    test "returns :not_found for unknown key" do
      name = unique_name(:status_unknown)
      start_limiter(name)

      assert :not_found = InboundLimiter.status(name, "never_seen")
    end

    test "does not increment the counter" do
      name = unique_name(:status_no_increment)
      start_limiter(name, limit: {10, :second})

      InboundLimiter.check(name, "key")
      {:ok, count1} = InboundLimiter.status(name, "key")
      {:ok, count2} = InboundLimiter.status(name, "key")
      {:ok, count3} = InboundLimiter.status(name, "key")

      # All should be approximately the same (decreasing slightly as window progresses)
      assert_in_delta count1, count2, 0.1
      assert_in_delta count2, count3, 0.1
    end
  end

  describe "reset/2" do
    test "clears exhausted key and re-allows requests" do
      name = unique_name(:reset_clears)
      start_limiter(name, limit: {1, :second})

      assert :ok = InboundLimiter.check(name, "key")
      assert {:rate_limited, _} = InboundLimiter.check(name, "key")

      InboundLimiter.reset(name, "key")

      assert :ok = InboundLimiter.check(name, "key")
    end

    test "returns :ok for unknown key" do
      name = unique_name(:reset_unknown)
      start_limiter(name)

      assert :ok = InboundLimiter.reset(name, "never_seen")
    end
  end

  describe "multiple instances" do
    test "separate instances have independent limits" do
      name1 = unique_name(:multi_1)
      name2 = unique_name(:multi_2)
      start_limiter(name1, limit: {1, :second})
      start_limiter(name2, limit: {5, :second})

      # Exhaust instance 1
      assert :ok = InboundLimiter.check(name1, "key")
      assert {:rate_limited, _} = InboundLimiter.check(name1, "key")

      # Instance 2 is independent
      for _ <- 1..5 do
        assert :ok = InboundLimiter.check(name2, "key")
      end
    end
  end

  describe "child_spec/1" do
    test "uses :name as child id" do
      spec = InboundLimiter.child_spec(name: :my_limiter, limit: {10, :minute})
      assert spec.id == :my_limiter
    end

    test "raises on missing :name" do
      assert_raise KeyError, fn ->
        InboundLimiter.child_spec(limit: {10, :minute})
      end
    end
  end

  describe "cleanup" do
    test "removes stale entries" do
      name = unique_name(:cleanup)
      # 1-second windows, cleanup every 50ms
      start_limiter(name, limit: {100, :second}, cleanup_interval_ms: 50)

      # Create some entries
      for i <- 1..10 do
        InboundLimiter.check(name, "key_#{i}")
      end

      assert :ets.info(name, :size) == 10

      # Entries become stale when window_id < current_wid - 2 (strictly less),
      # meaning 3 full windows must pass. Add buffer for cleanup cycle.
      Process.sleep(3_200)

      assert :ets.info(name, :size) == 0
    end
  end

  describe "concurrent access" do
    test "handles concurrent check calls without crashes" do
      name = unique_name(:concurrent)
      start_limiter(name, limit: {100, :second})

      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            InboundLimiter.check(name, "shared_key")
          end)
        end

      results = Task.await_many(tasks)

      # All results should be valid
      Enum.each(results, fn result ->
        assert result == :ok or match?({:rate_limited, _}, result)
      end)

      # Approximately 100 should be allowed (but allow variance for race conditions)
      ok_count = Enum.count(results, &(&1 == :ok))
      assert ok_count >= 45, "Expected most of 50 requests to be allowed with limit 100"
    end
  end

  describe "configuration" do
    test "accepts :second period" do
      name = unique_name(:period_second)
      start_limiter(name, limit: {5, :second})
      assert :ok = InboundLimiter.check(name, "key")
    end

    test "accepts :minute period" do
      name = unique_name(:period_minute)
      start_limiter(name, limit: {100, :minute})
      assert :ok = InboundLimiter.check(name, "key")
    end

    test "accepts :day period" do
      name = unique_name(:period_day)
      start_limiter(name, limit: {10_000, :day})
      assert :ok = InboundLimiter.check(name, "key")
    end

    test "accepts custom cleanup_interval_ms" do
      name = unique_name(:custom_cleanup)
      start_limiter(name, limit: {5, :second}, cleanup_interval_ms: 500)
      assert :ok = InboundLimiter.check(name, "key")
    end
  end
end
