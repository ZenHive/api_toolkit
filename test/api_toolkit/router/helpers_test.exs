defmodule ApiToolkit.Router.HelpersTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias ApiToolkit.Router.Helpers
  alias Plug.Conn.Unfetched

  # Stub endpoint module for testing dispatch
  defmodule StubEndpoint do
    def ok_endpoint(_params), do: {:ok, %{result: "success"}}
    def error_endpoint(_params), do: {:error, :not_found}
    def detailed_error(_params), do: {:error, :validation_failed, "name is required"}

    def echo_params(params), do: {:ok, params}
  end

  # Stub metrics module to verify recording
  defmodule StubMetrics do
    @moduledoc false
    def record(path, cache_status, duration_us) do
      send(self(), {:metrics_recorded, path, cache_status, duration_us})
      :ok
    end
  end

  describe "handle_endpoint/4" do
    test "returns 200 with JSON body on {:ok, data}" do
      conn =
        :get
        |> conn("/api/search?q=test")
        |> Plug.Conn.fetch_query_params()
        |> Helpers.handle_endpoint(StubEndpoint, :ok_endpoint, %{metrics: nil})

      assert conn.status == 200
      assert JSON.decode!(conn.resp_body) == %{"result" => "success"}
      assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers
    end

    test "returns 400 with error on {:error, reason}" do
      conn =
        :get
        |> conn("/api/missing")
        |> Plug.Conn.fetch_query_params()
        |> Helpers.handle_endpoint(StubEndpoint, :error_endpoint, %{metrics: nil})

      assert conn.status == 400
      assert JSON.decode!(conn.resp_body) == %{"error" => "not_found"}
    end

    test "returns 400 with error and detail on {:error, reason, detail}" do
      conn =
        :post
        |> conn("/api/create", "")
        |> Plug.Conn.fetch_query_params()
        |> Helpers.handle_endpoint(StubEndpoint, :detailed_error, %{metrics: nil})

      assert conn.status == 400
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "validation_failed"
      assert body["detail"] == "name is required"
    end

    test "records metrics when metrics module configured" do
      :get
      |> conn("/api/search?q=test")
      |> Plug.Conn.fetch_query_params()
      |> Helpers.handle_endpoint(StubEndpoint, :ok_endpoint, %{metrics: StubMetrics})

      assert_received {:metrics_recorded, "/api/search", :miss, duration_us}
      assert is_integer(duration_us)
      assert duration_us >= 0
    end

    test "skips metrics when metrics is nil" do
      :get
      |> conn("/api/search?q=test")
      |> Plug.Conn.fetch_query_params()
      |> Helpers.handle_endpoint(StubEndpoint, :ok_endpoint, %{metrics: nil})

      refute_received {:metrics_recorded, _, _, _}
    end
  end

  describe "merge_params/1" do
    test "merges query and body params with body taking precedence" do
      conn =
        :post
        |> conn("/api/search?q=hello&format=json", JSON.encode!(%{q: "world", extra: "value"}))
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:json], json_decoder: JSON))

      params = Helpers.merge_params(conn)
      # Body "q" overwrites query "q"
      assert params["q"] == "world"
      # Query-only param preserved
      assert params["format"] == "json"
      # Body-only param preserved
      assert params["extra"] == "value"
    end

    test "returns query params when body is unfetched" do
      conn =
        :get
        |> conn("/api/search?q=hello")
        |> Plug.Conn.fetch_query_params()

      params = Helpers.merge_params(conn)
      assert params["q"] == "hello"
    end

    test "returns empty map when no params" do
      conn =
        :get
        |> conn("/api/search")
        |> Plug.Conn.fetch_query_params()

      params = Helpers.merge_params(conn)
      assert params == %{}
    end

    test "fetches query params when unfetched" do
      conn = conn(:get, "/api/search?q=hello")

      # query_params are unfetched — this is the default in Plug.Router
      assert %Unfetched{} = conn.query_params

      params = Helpers.merge_params(conn)
      assert params["q"] == "hello"
    end

    test "handles both query and body unfetched" do
      conn = conn(:get, "/api/search")
      assert %Unfetched{} = conn.query_params
      assert %Unfetched{} = conn.body_params

      params = Helpers.merge_params(conn)
      assert params == %{}
    end
  end

  describe "handle_endpoint passes merged params to function" do
    test "endpoint receives merged query and body params" do
      conn =
        :get
        |> conn("/api/echo?key=value")
        |> Plug.Conn.fetch_query_params()
        |> Helpers.handle_endpoint(StubEndpoint, :echo_params, %{metrics: nil})

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["key"] == "value"
    end

    test "works with unfetched query params (plain Plug.Router)" do
      conn =
        :get
        |> conn("/api/echo?key=value")
        |> Helpers.handle_endpoint(StubEndpoint, :echo_params, %{metrics: nil})

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["key"] == "value"
    end
  end
end
