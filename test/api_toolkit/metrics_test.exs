defmodule ApiToolkit.MetricsTest do
  use ExUnit.Case, async: false

  alias ApiToolkit.Metrics

  setup do
    start_supervised!(Metrics)
    Metrics.reset()
    :ok
  end

  describe "record/3" do
    test "records a cache hit" do
      Metrics.record("/test/endpoint", :hit, 1000)

      metrics = Metrics.get_all()
      assert metrics["/test/endpoint"].cache_hits == 1
      assert metrics["/test/endpoint"].cache_misses == 0
    end

    test "records a cache miss" do
      Metrics.record("/test/endpoint", :miss, 2000)

      metrics = Metrics.get_all()
      assert metrics["/test/endpoint"].cache_hits == 0
      assert metrics["/test/endpoint"].cache_misses == 1
    end

    test "accumulates multiple requests" do
      Metrics.record("/test/endpoint", :hit, 100)
      Metrics.record("/test/endpoint", :hit, 200)
      Metrics.record("/test/endpoint", :miss, 300)

      metrics = Metrics.get_all()
      assert metrics["/test/endpoint"].total_requests == 3
      assert metrics["/test/endpoint"].cache_hits == 2
      assert metrics["/test/endpoint"].cache_misses == 1
    end

    test "tracks separate endpoints independently" do
      Metrics.record("/endpoint/a", :hit, 100)
      Metrics.record("/endpoint/b", :miss, 200)

      metrics = Metrics.get_all()
      assert metrics["/endpoint/a"].cache_hits == 1
      assert metrics["/endpoint/b"].cache_misses == 1
    end
  end

  describe "get_all/0" do
    test "returns empty map when no metrics recorded" do
      assert Metrics.get_all() == %{}
    end

    test "calculates hit_rate correctly" do
      Metrics.record("/test", :hit, 100)
      Metrics.record("/test", :hit, 100)
      Metrics.record("/test", :miss, 100)

      metrics = Metrics.get_all()
      # 2 hits / 3 total = 0.667
      assert metrics["/test"].hit_rate == 0.667
    end

    test "calculates avg_duration_us" do
      Metrics.record("/test", :hit, 100)
      Metrics.record("/test", :miss, 300)

      metrics = Metrics.get_all()
      # (100 + 300) / 2 = 200
      assert metrics["/test"].avg_duration_us == 200
    end

    test "tracks last_request_at" do
      before = System.system_time(:second)
      Metrics.record("/test", :hit, 100)
      after_time = System.system_time(:second)

      metrics = Metrics.get_all()
      assert metrics["/test"].last_request_at >= before
      assert metrics["/test"].last_request_at <= after_time
    end
  end

  describe "summary/0" do
    test "returns totals across all endpoints" do
      Metrics.record("/a", :hit, 100)
      Metrics.record("/a", :miss, 200)
      Metrics.record("/b", :hit, 300)

      summary = Metrics.summary()
      assert summary.total_requests == 3
      assert summary.total_cache_hits == 2
      assert summary.total_cache_misses == 1
      assert summary.endpoints_count == 2
    end

    test "calculates overall_hit_rate" do
      Metrics.record("/a", :hit, 100)
      Metrics.record("/b", :miss, 100)

      summary = Metrics.summary()
      # 1 hit / 2 total = 0.5
      assert summary.overall_hit_rate == 0.5
    end

    test "includes by_endpoint details" do
      Metrics.record("/test", :hit, 100)

      summary = Metrics.summary()
      assert is_map(summary.by_endpoint)
      assert summary.by_endpoint["/test"].total_requests == 1
    end
  end

  describe "reset/0" do
    test "clears all metrics" do
      Metrics.record("/test", :hit, 100)
      assert Metrics.get_all() != %{}

      Metrics.reset()
      assert Metrics.get_all() == %{}
    end
  end
end
