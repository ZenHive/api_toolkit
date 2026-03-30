defmodule ApiToolkit.Plug.RateLimit do
  @moduledoc """
  Per-IP rate limiting plug wrapping `ApiToolkit.InboundLimiter`.

  Returns 429 with `Retry-After` header and JSON error body when the limit
  is exceeded. Optionally records rejections via `ApiToolkit.Rejections`.

  ## Usage

      # Basic — requires an InboundLimiter instance in your supervision tree
      plug ApiToolkit.Plug.RateLimit, limiter: MyApp.RateLimiter

      # With skip paths and rejection recording
      plug ApiToolkit.Plug.RateLimit,
        limiter: MyApp.RateLimiter,
        skip_paths: ["/health", "/metrics"],
        rejections: MyApp.Rejections,
        rejection_type: :rate_limited

  ## Options

  - `:limiter` — Required. The `ApiToolkit.InboundLimiter` name to check against.
  - `:skip_paths` — List of paths to bypass rate limiting (default: `["/health"]`).
  - `:rejections` — Optional `ApiToolkit.Rejections` server name for recording
    rejections. `nil` disables recording (default: `nil`).
  - `:rejection_type` — Atom passed to `Rejections.record/3` (default: `:rate_limited`).
  """

  @behaviour Plug

  import Plug.Conn

  @default_skip_paths ["/health"]

  @impl true
  def init(opts) do
    %{
      limiter: Keyword.fetch!(opts, :limiter),
      skip_paths: Keyword.get(opts, :skip_paths, @default_skip_paths),
      rejections: Keyword.get(opts, :rejections),
      rejection_type: Keyword.get(opts, :rejection_type, :rate_limited)
    }
  end

  @impl true
  def call(conn, %{skip_paths: skip_paths} = opts) do
    if conn.request_path in skip_paths do
      conn
    else
      check_rate(conn, opts)
    end
  end

  defp check_rate(conn, %{limiter: limiter} = opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case ApiToolkit.InboundLimiter.check(limiter, ip) do
      :ok ->
        conn

      {:rate_limited, retry_after_ms} ->
        maybe_record_rejection(opts, conn.request_path)
        reject(conn, retry_after_ms)
    end
  end

  defp maybe_record_rejection(%{rejections: nil}, _path), do: :ok

  defp maybe_record_rejection(%{rejections: server, rejection_type: type}, path) do
    ApiToolkit.Rejections.record(server, type, path)
  end

  defp reject(conn, retry_after_ms) do
    retry_after_s = max(1, ceil(retry_after_ms / 1000))

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("retry-after", to_string(retry_after_s))
    |> send_resp(429, JSON.encode!(%{error: "rate_limited", retry_after: retry_after_s}))
    |> halt()
  end
end
