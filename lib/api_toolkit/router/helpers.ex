defmodule ApiToolkit.Router.Helpers do
  @moduledoc """
  Reusable Plug.Router utilities for API dispatch.

  Provides `handle_endpoint/3,4` for dispatching to endpoint functions with
  JSON responses and optional metrics recording, and `merge_params/1` for
  merging query and body parameters.

  ## Usage

      defmodule MyApp.Router do
        use Plug.Router

        plug :match
        plug :dispatch

        get "/api/search" do
          ApiToolkit.Router.Helpers.handle_endpoint(conn, MyApp.Search, :search)
        end

        # With options
        @opts %{metrics: MyApp.Metrics}
        get "/api/premium" do
          ApiToolkit.Router.Helpers.handle_endpoint(conn, MyApp.Premium, :fetch, @opts)
        end
      end

  ## Options for `handle_endpoint/4`

  - `:metrics` — Module implementing `record/3` (default: `ApiToolkit.Metrics`).
    Set to `nil` to disable metrics recording.
  """

  import Plug.Conn

  @default_opts %{metrics: ApiToolkit.Metrics}

  @doc """
  Calls an endpoint function with merged params and returns a JSON response.

  Dispatches to `module.function(params)` and translates the result:
  - `{:ok, data}` → 200 with JSON body
  - `{:error, reason, detail}` → 400 with JSON error
  - `{:error, reason}` → 400 with JSON error

  Records request metrics (path, cache status, duration) when a metrics
  module is configured.
  """
  @spec handle_endpoint(Plug.Conn.t(), module(), atom(), map()) :: Plug.Conn.t()
  def handle_endpoint(conn, module, function, opts \\ @default_opts) do
    params = merge_params(conn)
    start = System.monotonic_time(:microsecond)

    result = apply(module, function, [params])

    duration_us = System.monotonic_time(:microsecond) - start
    maybe_record_metrics(opts, conn.request_path, duration_us)

    send_result(conn, result)
  end

  @doc """
  Merges query string params with JSON body params (body takes precedence).

  Handles the case where body params haven't been fetched yet
  (`Plug.Conn.Unfetched`).
  """
  @spec merge_params(Plug.Conn.t()) :: %{String.t() => term()}
  def merge_params(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    body =
      case conn.body_params do
        %Plug.Conn.Unfetched{} -> %{}
        params -> params
      end

    Map.merge(conn.query_params, body)
  end

  # Records metrics if a metrics module is configured.
  # Always passes :miss for cache_status — the router doesn't know about caching;
  # endpoint functions handle cache logic internally via ApiToolkit.Cache.
  defp maybe_record_metrics(%{metrics: nil}, _path, _duration_us), do: :ok
  defp maybe_record_metrics(%{metrics: mod}, path, duration_us), do: mod.record(path, :miss, duration_us)
  defp maybe_record_metrics(_opts, _path, _duration_us), do: :ok

  # Sends JSON response based on the result tuple
  defp send_result(conn, {:ok, data}), do: json_resp(conn, 200, data)

  defp send_result(conn, {:error, reason, detail}), do: json_resp(conn, 400, %{error: to_string(reason), detail: detail})

  defp send_result(conn, {:error, reason}), do: json_resp(conn, 400, %{error: to_string(reason)})

  defp json_resp(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
