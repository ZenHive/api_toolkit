defmodule ApiToolkit.RejectionsTest do
  use ExUnit.Case, async: false

  @server __MODULE__.Rejections

  setup do
    start_supervised!({ApiToolkit.Rejections, name: @server})
    :ok
  end

  describe "record/3" do
    test "increments counter for a rejection type" do
      ApiToolkit.Rejections.record(@server, :rate_limited, "/api/search")
      ApiToolkit.Rejections.record(@server, :rate_limited, "/api/search")

      summary = ApiToolkit.Rejections.summary(@server)
      assert summary.by_type.rate_limited.total == 2
      assert summary.by_type.rate_limited.by_path["/api/search"].count == 2
    end

    test "tracks separate paths independently" do
      ApiToolkit.Rejections.record(@server, :rate_limited, "/api/search")
      ApiToolkit.Rejections.record(@server, :rate_limited, "/api/validate")
      ApiToolkit.Rejections.record(@server, :rate_limited, "/api/search")

      summary = ApiToolkit.Rejections.summary(@server)
      assert summary.by_type.rate_limited.by_path["/api/search"].count == 2
      assert summary.by_type.rate_limited.by_path["/api/validate"].count == 1
      assert summary.by_type.rate_limited.total == 3
    end

    test "tracks separate types independently for same path" do
      ApiToolkit.Rejections.record(@server, :rate_limited, "/api/premium")
      ApiToolkit.Rejections.record(@server, :payment_required, "/api/premium")

      summary = ApiToolkit.Rejections.summary(@server)
      assert summary.by_type.rate_limited.by_path["/api/premium"].count == 1
      assert summary.by_type.payment_required.by_path["/api/premium"].count == 1
    end

    test "accepts any atom as rejection type" do
      ApiToolkit.Rejections.record(@server, :custom_reason, "/api/foo")

      summary = ApiToolkit.Rejections.summary(@server)
      assert summary.by_type.custom_reason.total == 1
    end

    test "records last_rejected_at timestamp" do
      ApiToolkit.Rejections.record(@server, :rate_limited, "/api/search")

      summary = ApiToolkit.Rejections.summary(@server)
      ts = summary.by_type.rate_limited.by_path["/api/search"].last_rejected_at
      assert is_integer(ts)
      assert_in_delta ts, System.system_time(:second), 5
    end
  end

  describe "summary/1" do
    test "returns zero totals when no rejections recorded" do
      summary = ApiToolkit.Rejections.summary(@server)

      assert summary.total_rejections == 0
      assert summary.by_type == %{}
    end

    test "computes total_rejections across all types" do
      ApiToolkit.Rejections.record(@server, :rate_limited, "/a")
      ApiToolkit.Rejections.record(@server, :rate_limited, "/b")
      ApiToolkit.Rejections.record(@server, :payment_required, "/c")

      assert ApiToolkit.Rejections.summary(@server).total_rejections == 3
    end
  end

  describe "get_all/1" do
    test "returns raw ETS tuples" do
      ApiToolkit.Rejections.record(@server, :rate_limited, "/api/search")

      rows = ApiToolkit.Rejections.get_all(@server)
      assert [{{:rate_limited, "/api/search"}, 1, _ts}] = rows
    end
  end

  describe "reset/1" do
    test "clears all rejection data" do
      ApiToolkit.Rejections.record(@server, :rate_limited, "/a")
      ApiToolkit.Rejections.record(@server, :payment_required, "/b")
      ApiToolkit.Rejections.reset(@server)

      assert ApiToolkit.Rejections.get_all(@server) == []
      assert ApiToolkit.Rejections.summary(@server).total_rejections == 0
    end
  end
end
