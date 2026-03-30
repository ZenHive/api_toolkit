defmodule ApiToolkit.MCP.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ApiToolkit.MCP

  @opts MCP.Plug.init(handler: ApiToolkit.TestMCPHandler)
  @opts_with_assigns MCP.Plug.init(handler: ApiToolkit.TestMCPHandler, assigns: %{greeting_prefix: "Howdy"})

  # Helper to send a JSON-RPC request through the plug
  defp post_json(body, opts \\ @opts) do
    :post
    |> conn("/", JSON.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> MCP.Plug.call(opts)
  end

  defp json_body(conn), do: JSON.decode!(conn.resp_body)

  describe "POST with valid JSON-RPC" do
    test "ping returns 200 with empty result" do
      conn = post_json(%{jsonrpc: "2.0", method: "ping", id: 1})

      assert conn.status == 200
      assert conn |> get_resp_header("content-type") |> hd() =~ "application/json"

      body = json_body(conn)
      assert body["jsonrpc"] == "2.0"
      assert body["id"] == 1
      assert body["result"] == %{}
    end

    test "initialize returns 200 with server info and tools" do
      conn = post_json(%{jsonrpc: "2.0", method: "initialize", id: 1, params: %{protocolVersion: "2025-03-26"}})

      assert conn.status == 200
      body = json_body(conn)
      assert body["result"]["protocolVersion"] == "2025-03-26"
      assert body["result"]["serverInfo"]["name"] == "test-mcp-server"
      assert length(body["result"]["tools"]) == 6
    end

    test "tools/call dispatches and returns content" do
      conn = post_json(%{jsonrpc: "2.0", method: "tools/call", id: 1, params: %{name: "echo", arguments: %{text: "hi"}}})

      assert conn.status == 200
      body = json_body(conn)
      assert body["result"]["content"] == [%{"type" => "text", "text" => "hi"}]
    end

    test "tools/call passes assigns to arity-2 callbacks" do
      conn =
        post_json(
          %{jsonrpc: "2.0", method: "tools/call", id: 1, params: %{name: "greet", arguments: %{name: "Tito"}}},
          @opts_with_assigns
        )

      assert conn.status == 200
      body = json_body(conn)
      assert body["result"]["content"] == [%{"type" => "text", "text" => "Howdy, Tito!"}]
    end

    test "tools/call catches exceptions and returns isError" do
      conn = post_json(%{jsonrpc: "2.0", method: "tools/call", id: 1, params: %{name: "crash", arguments: %{}}})

      assert conn.status == 200
      body = json_body(conn)
      assert body["result"]["isError"] == true
      assert hd(body["result"]["content"])["text"] =~ "intentional crash"
    end
  end

  describe "notifications" do
    test "returns 202 with empty body" do
      conn = post_json(%{jsonrpc: "2.0", method: "notifications/initialized"})

      assert conn.status == 202
      assert conn.resp_body == ""
    end
  end

  describe "error handling" do
    test "invalid JSON-RPC returns 400" do
      conn = post_json(%{not: "valid"})

      assert conn.status == 400
      body = json_body(conn)
      assert body["error"]["code"] == -32_600
    end

    test "empty parsed JSON body returns invalid JSON-RPC, not parse error" do
      # When Plug.Parsers parses valid JSON "{}", body_params becomes %{}.
      # This must route to Handler (→ -32600 invalid JSON-RPC), not raw body read (→ -32700).
      conn =
        :post
        |> conn("/", "")
        |> put_req_header("content-type", "application/json")
        |> Map.put(:body_params, %{})
        |> MCP.Plug.call(@opts)

      assert conn.status == 400
      body = json_body(conn)
      assert body["error"]["code"] == -32_600
    end

    test "invalid JSON body returns parse error" do
      conn =
        :post
        |> conn("/", "not json at all")
        |> put_req_header("content-type", "application/json")
        |> MCP.Plug.call(@opts)

      assert conn.status == 400
      body = json_body(conn)
      assert body["error"]["code"] == -32_700
      assert body["error"]["message"] =~ "Parse error"
    end
  end

  describe "non-POST methods" do
    test "GET returns 405 with Allow header" do
      conn =
        :get
        |> conn("/")
        |> MCP.Plug.call(@opts)

      assert conn.status == 405
      assert get_resp_header(conn, "allow") == ["POST"]
    end

    test "PUT returns 405" do
      conn =
        :put
        |> conn("/", "")
        |> MCP.Plug.call(@opts)

      assert conn.status == 405
    end
  end

  describe "batch requests" do
    test "handles Plug.Parsers _json wrapping of top-level arrays" do
      # When Plug.Parsers parses a top-level JSON array, it wraps it as %{"_json" => [...]}
      wrapped_body = %{
        "_json" => [
          %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1},
          %{"jsonrpc" => "2.0", "method" => "ping", "id" => 2}
        ]
      }

      conn =
        :post
        |> conn("/", "")
        |> put_req_header("content-type", "application/json")
        |> Map.put(:body_params, wrapped_body)
        |> MCP.Plug.call(@opts)

      assert conn.status == 200
      body = json_body(conn)
      assert is_list(body)
      assert length(body) == 2
      assert Enum.all?(body, &(&1["result"] == %{}))
    end

    test "rejects initialize inside a batch" do
      conn =
        post_json([
          %{jsonrpc: "2.0", method: "initialize", id: 1, params: %{protocolVersion: "2025-03-26"}},
          %{jsonrpc: "2.0", method: "ping", id: 2}
        ])

      assert conn.status == 400
      body = json_body(conn)
      assert body["error"]["code"] == -32_600
      assert body["error"]["message"] =~ "initialize must not be part of a batch"
    end

    test "processes batch array and returns array of responses" do
      conn =
        post_json([
          %{jsonrpc: "2.0", method: "ping", id: 1},
          %{jsonrpc: "2.0", method: "ping", id: 2}
        ])

      assert conn.status == 200
      body = json_body(conn)
      assert is_list(body)
      assert length(body) == 2
      assert Enum.all?(body, &(&1["result"] == %{}))
    end

    test "batch of only notifications returns 202" do
      conn =
        post_json([
          %{jsonrpc: "2.0", method: "notifications/initialized"},
          %{jsonrpc: "2.0", method: "notifications/cancelled"}
        ])

      assert conn.status == 202
      assert conn.resp_body == ""
    end

    test "empty batch returns 400" do
      conn = post_json([])

      assert conn.status == 400
      body = json_body(conn)
      assert body["error"]["code"] == -32_600
      assert body["error"]["message"] =~ "empty batch"
    end
  end

  describe "resources and prompts through Plug" do
    @full_opts MCP.Plug.init(handler: ApiToolkit.TestMCPHandlerFull)

    test "resources/list returns 200 with resources array" do
      conn = post_json(%{jsonrpc: "2.0", method: "resources/list", id: 1}, @full_opts)

      assert conn.status == 200
      body = json_body(conn)
      resources = body["result"]["resources"]
      assert length(resources) == 2
      assert Enum.any?(resources, &(&1["uri"] == "api:///openapi.json"))
    end

    test "resources/read returns 200 with contents" do
      conn =
        post_json(%{jsonrpc: "2.0", method: "resources/read", id: 1, params: %{uri: "api:///openapi.json"}}, @full_opts)

      assert conn.status == 200
      body = json_body(conn)
      [content] = body["result"]["contents"]
      assert content["uri"] == "api:///openapi.json"
      assert content["text"] =~ "3.1.0"
    end

    test "prompts/list returns 200 with prompts array" do
      conn = post_json(%{jsonrpc: "2.0", method: "prompts/list", id: 1}, @full_opts)

      assert conn.status == 200
      body = json_body(conn)
      prompts = body["result"]["prompts"]
      assert length(prompts) == 2
      assert Enum.any?(prompts, &(&1["name"] == "search_help"))
    end

    test "prompts/get returns 200 with messages" do
      conn =
        post_json(
          %{jsonrpc: "2.0", method: "prompts/get", id: 1, params: %{name: "greeting"}},
          @full_opts
        )

      assert conn.status == 200
      body = json_body(conn)
      [message] = body["result"]["messages"]
      assert message["role"] == "user"
      assert message["content"]["text"] =~ "Hello"
    end
  end

  describe "connection state" do
    test "all responses halt the connection" do
      conn = post_json(%{jsonrpc: "2.0", method: "ping", id: 1})
      assert conn.halted

      conn = post_json(%{jsonrpc: "2.0", method: "notifications/initialized"})
      assert conn.halted

      conn =
        :get
        |> conn("/")
        |> MCP.Plug.call(@opts)

      assert conn.halted
    end
  end
end
