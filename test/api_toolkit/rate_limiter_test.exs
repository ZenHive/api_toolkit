defmodule ApiToolkit.RateLimiterTest do
  use ExUnit.Case, async: true

  alias ApiToolkit.RateLimiter

  describe "acquire/1" do
    test "allows immediate acquisition when tokens available" do
      {:ok, limiter} = RateLimiter.start_link(name: :test_limiter_1, rate: {5, :second})

      assert :ok = RateLimiter.acquire(limiter)
      assert :ok = RateLimiter.acquire(limiter)
      assert :ok = RateLimiter.acquire(limiter)
    end

    test "blocks when no tokens available" do
      {:ok, limiter} = RateLimiter.start_link(name: :test_limiter_2, rate: {1, :second})

      assert :ok = RateLimiter.acquire(limiter)

      task =
        Task.async(fn ->
          start = System.monotonic_time(:millisecond)
          :ok = RateLimiter.acquire(limiter)
          elapsed = System.monotonic_time(:millisecond) - start
          elapsed
        end)

      elapsed = Task.await(task, 2000)
      assert elapsed >= 900, "Expected to wait ~1s, but only waited #{elapsed}ms"
    end
  end

  describe "rate configurations" do
    test "accepts :second period" do
      {:ok, _} = RateLimiter.start_link(name: :test_second, rate: {1, :second})
    end

    test "accepts :minute period" do
      {:ok, _} = RateLimiter.start_link(name: :test_minute, rate: {60, :minute})
    end

    test "accepts :day period" do
      {:ok, _} = RateLimiter.start_link(name: :test_day, rate: {25, :day})
    end
  end

  describe "status/1" do
    test "returns tokens_available, max_tokens, and queue_depth" do
      {:ok, limiter} = RateLimiter.start_link(name: :test_status_1, rate: {5, :second})

      status = RateLimiter.status(limiter)

      assert status.tokens_available == 5
      assert status.max_tokens == 5
      assert status.queue_depth == 0
    end

    test "reflects current state after acquiring tokens" do
      {:ok, limiter} = RateLimiter.start_link(name: :test_status_2, rate: {3, :second})

      :ok = RateLimiter.acquire(limiter)
      :ok = RateLimiter.acquire(limiter)

      status = RateLimiter.status(limiter)

      assert status.tokens_available == 1
      assert status.max_tokens == 3
      assert status.queue_depth == 0
    end

    test "does not consume a token" do
      {:ok, limiter} = RateLimiter.start_link(name: :test_status_3, rate: {2, :second})

      status1 = RateLimiter.status(limiter)
      status2 = RateLimiter.status(limiter)
      status3 = RateLimiter.status(limiter)

      assert status1.tokens_available == 2
      assert status2.tokens_available == 2
      assert status3.tokens_available == 2
    end
  end
end
