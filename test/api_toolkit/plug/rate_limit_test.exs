defmodule ApiToolkit.Plug.RateLimitTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias ApiToolkit.Plug.RateLimit

  @limiter :"#{__MODULE__}.Limiter"
  @rejections :"#{__MODULE__}.Rejections"
  @limit 5

  setup do
    start_supervised!({ApiToolkit.InboundLimiter, name: @limiter, limit: {@limit, :minute}})
    :ok
  end

  # Builds a conn and runs it through the plug
  defp rate_check(path, opts, ip \\ {127, 0, 0, 1}) do
    :get
    |> conn(path)
    |> Map.put(:remote_ip, ip)
    |> RateLimit.call(opts)
  end

  defp default_opts, do: RateLimit.init(limiter: @limiter)

  describe "rate limiting" do
    test "allows requests within the limit" do
      opts = default_opts()

      for _ <- 1..@limit do
        conn = rate_check("/api/search", opts)
        refute conn.halted
      end
    end

    test "returns 429 when limit exceeded" do
      opts = default_opts()
      for _ <- 1..@limit, do: rate_check("/api/search", opts)

      conn = rate_check("/api/search", opts)
      assert conn.status == 429
      assert conn.halted

      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "rate_limited"
      assert is_integer(body["retry_after"])
      assert body["retry_after"] >= 1
    end

    test "includes Retry-After header on 429" do
      opts = default_opts()
      for _ <- 1..@limit, do: rate_check("/api/search", opts)

      conn = rate_check("/api/search", opts)
      assert conn.status == 429

      [retry_after] = Plug.Conn.get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) >= 1
    end

    test "rate limits are per-IP" do
      opts = default_opts()
      ip_a = {10, 0, 0, 1}
      ip_b = {10, 0, 0, 2}

      for _ <- 1..@limit, do: rate_check("/api/search", opts, ip_a)

      # IP A is limited
      conn_a = rate_check("/api/search", opts, ip_a)
      assert conn_a.status == 429

      # IP B still has budget
      conn_b = rate_check("/api/search", opts, ip_b)
      refute conn_b.halted
    end
  end

  describe "skip paths" do
    test "/health is skipped by default" do
      opts = default_opts()

      for _ <- 1..(@limit + 5) do
        conn = rate_check("/health", opts)
        refute conn.halted
      end
    end

    test "custom skip paths are respected" do
      opts = RateLimit.init(limiter: @limiter, skip_paths: ["/health", "/metrics"])

      for _ <- 1..(@limit + 5) do
        conn = rate_check("/metrics", opts)
        refute conn.halted
      end
    end
  end

  describe "rejection recording" do
    test "records rejections when rejections server configured" do
      start_supervised!({ApiToolkit.Rejections, name: @rejections})
      opts = RateLimit.init(limiter: @limiter, rejections: @rejections)

      for _ <- 1..@limit, do: rate_check("/api/search", opts)
      rate_check("/api/search", opts)

      summary = ApiToolkit.Rejections.summary(@rejections)
      assert summary.by_type.rate_limited.total == 1
    end

    test "uses custom rejection type" do
      start_supervised!({ApiToolkit.Rejections, name: @rejections})
      opts = RateLimit.init(limiter: @limiter, rejections: @rejections, rejection_type: :throttled)

      for _ <- 1..@limit, do: rate_check("/api/search", opts)
      rate_check("/api/search", opts)

      summary = ApiToolkit.Rejections.summary(@rejections)
      assert summary.by_type.throttled.total == 1
    end

    test "works without rejection recording (default)" do
      opts = default_opts()
      for _ <- 1..@limit, do: rate_check("/api/search", opts)

      # Should not crash — rejections: nil by default
      conn = rate_check("/api/search", opts)
      assert conn.status == 429
    end
  end
end
