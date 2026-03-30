defmodule ApiToolkit.Plug.RemoteIpTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ApiToolkit.Plug.RemoteIp

  @default_opts RemoteIp.init([])

  # Builds a conn with the given header and runs the plug
  defp with_header(header, ip_string, opts \\ @default_opts) do
    :get
    |> conn("/")
    |> put_req_header(header, ip_string)
    |> RemoteIp.call(opts)
  end

  defp without_header(opts \\ @default_opts) do
    :get
    |> conn("/")
    |> RemoteIp.call(opts)
  end

  describe "default header (fly-client-ip)" do
    test "rewrites conn.remote_ip from IPv4 header" do
      conn = with_header("fly-client-ip", "203.0.113.42")
      assert conn.remote_ip == {203, 0, 113, 42}
    end

    test "rewrites conn.remote_ip from IPv6 header" do
      conn = with_header("fly-client-ip", "2001:db8::1")
      assert conn.remote_ip == {8193, 3512, 0, 0, 0, 0, 0, 1}
    end
  end

  describe "header absent" do
    test "leaves conn.remote_ip unchanged" do
      conn = without_header()
      assert conn.remote_ip == {127, 0, 0, 1}
    end
  end

  describe "invalid header value" do
    test "leaves conn.remote_ip unchanged for garbage input" do
      conn = with_header("fly-client-ip", "not-an-ip")
      assert conn.remote_ip == {127, 0, 0, 1}
    end

    test "leaves conn.remote_ip unchanged for empty string" do
      conn = with_header("fly-client-ip", "")
      assert conn.remote_ip == {127, 0, 0, 1}
    end
  end

  describe "comma-separated IPs (x-forwarded-for style)" do
    test "extracts first IP from comma-separated list" do
      opts = RemoteIp.init(header: "x-forwarded-for")
      conn = with_header("x-forwarded-for", "198.51.100.7, 203.0.113.1", opts)
      assert conn.remote_ip == {198, 51, 100, 7}
    end

    test "extracts first IP from list with spaces" do
      opts = RemoteIp.init(header: "x-forwarded-for")
      conn = with_header("x-forwarded-for", "  10.0.0.1 , 10.0.0.2 , 10.0.0.3", opts)
      assert conn.remote_ip == {10, 0, 0, 1}
    end

    test "handles single IP (no comma)" do
      opts = RemoteIp.init(header: "x-forwarded-for")
      conn = with_header("x-forwarded-for", "203.0.113.42", opts)
      assert conn.remote_ip == {203, 0, 113, 42}
    end

    test "extracts first IPv6 from comma-separated list" do
      opts = RemoteIp.init(header: "x-forwarded-for")
      conn = with_header("x-forwarded-for", "2001:db8::1, 2001:db8::2", opts)
      assert conn.remote_ip == {8193, 3512, 0, 0, 0, 0, 0, 1}
    end
  end

  describe "custom header" do
    test "reads from cf-connecting-ip when configured" do
      opts = RemoteIp.init(header: "cf-connecting-ip")
      conn = with_header("cf-connecting-ip", "198.51.100.7", opts)
      assert conn.remote_ip == {198, 51, 100, 7}
    end

    test "reads from x-real-ip when configured" do
      opts = RemoteIp.init(header: "x-real-ip")
      conn = with_header("x-real-ip", "10.0.0.1", opts)
      assert conn.remote_ip == {10, 0, 0, 1}
    end

    test "ignores default header when custom header configured" do
      opts = RemoteIp.init(header: "cf-connecting-ip")
      conn = with_header("fly-client-ip", "203.0.113.42", opts)
      assert conn.remote_ip == {127, 0, 0, 1}
    end
  end
end
