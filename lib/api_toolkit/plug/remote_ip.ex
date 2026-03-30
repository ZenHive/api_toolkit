defmodule ApiToolkit.Plug.RemoteIp do
  @moduledoc """
  Rewrites `conn.remote_ip` from a trusted reverse proxy header.

  Most reverse proxies (Fly.io, Cloudflare, Nginx) set a header with the
  real client IP. This plug reads that header and overwrites `conn.remote_ip`
  so downstream code (rate limiting, logging, analytics) sees the actual
  client address.

  No-op when the header is absent (local dev/test) or contains an
  unparseable value. Supports both IPv4 and IPv6.

  ## Usage

      plug ApiToolkit.Plug.RemoteIp
      plug ApiToolkit.Plug.RemoteIp, header: "cf-connecting-ip"
      plug ApiToolkit.Plug.RemoteIp, header: "x-real-ip"

  ## Options

  - `:header` — The header name to read the client IP from.
    Defaults to `"fly-client-ip"`. Common values: `"cf-connecting-ip"`,
    `"x-real-ip"`, `"x-forwarded-for"`.
  """

  @behaviour Plug

  @default_header "fly-client-ip"

  @impl true
  def init(opts) do
    %{header: Keyword.get(opts, :header, @default_header)}
  end

  @impl true
  def call(conn, %{header: header}) do
    case Plug.Conn.get_req_header(conn, header) do
      [ip_string] -> rewrite(conn, ip_string)
      _other -> conn
    end
  end

  # Extracts the first IP from a potentially comma-separated list (x-forwarded-for style)
  # and overwrites conn.remote_ip on success.
  defp rewrite(conn, ip_string) do
    ip_string
    |> extract_first_ip()
    |> to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, ip_tuple} -> %{conn | remote_ip: ip_tuple}
      {:error, _} -> conn
    end
  end

  # Handles comma-separated values like "198.51.100.7, 203.0.113.1"
  # by extracting the leftmost (client) IP.
  defp extract_first_ip(ip_string) do
    ip_string |> String.split(",", parts: 2) |> hd() |> String.trim()
  end
end
