defmodule ApiToolkit.MCP.HandlerTest do
  use ExUnit.Case, async: true

  alias ApiToolkit.MCP.Handler

  @handler ApiToolkit.TestMCPHandler

  # Helper to build a JSON-RPC request
  defp request(method, id, params \\ %{}) do
    %{"jsonrpc" => "2.0", "method" => method, "id" => id, "params" => params}
  end

  # Helper to build a JSON-RPC notification
  defp notification(method) do
    %{"jsonrpc" => "2.0", "method" => method}
  end

  describe "initialize" do
    test "returns protocol version, capabilities, server info, and tools" do
      msg = request("initialize", 1, %{"protocolVersion" => "2025-03-26"})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.jsonrpc == "2.0"
      assert response.id == 1

      result = response.result
      assert result.protocolVersion == "2025-03-26"
      assert result.serverInfo == %{name: "test-mcp-server", version: "0.1.0"}
      assert %{tools: %{listChanged: false}} = result.capabilities

      # Tools should be present without callback keys
      assert is_list(result.tools)
      assert length(result.tools) == 6

      echo_tool = Enum.find(result.tools, &(&1.name == "echo"))
      assert echo_tool.description == "Echoes back the input text"
      assert echo_tool.inputSchema.type == "object"
      refute Map.has_key?(echo_tool, :callback)
    end

    test "rejects missing protocol version" do
      msg = request("initialize", 1, %{})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "protocolVersion"
    end

    test "responds with server version for older client version (negotiation)" do
      msg = request("initialize", 1, %{"protocolVersion" => "2024-01-01"})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result.protocolVersion == "2025-03-26"
      assert response.result.serverInfo.name == "test-mcp-server"
    end

    test "responds with server version for newer client version (negotiation)" do
      msg = request("initialize", 1, %{"protocolVersion" => "2026-01-01"})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result.protocolVersion == "2025-03-26"
    end
  end

  describe "ping" do
    test "returns empty result" do
      msg = request("ping", 1)

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response == %{jsonrpc: "2.0", id: 1, result: %{}}
    end
  end

  describe "tools/list" do
    test "returns all tools without callbacks" do
      msg = request("tools/list", 1)

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      tools = response.result.tools
      assert length(tools) == 6

      names = Enum.map(tools, & &1.name)
      assert "echo" in names
      assert "greet" in names
      assert "crash" in names

      Enum.each(tools, fn tool ->
        refute Map.has_key?(tool, :callback)
        assert is_binary(tool.description)
        assert is_map(tool.inputSchema)
      end)
    end
  end

  describe "tools/call" do
    test "dispatches to arity-1 callback (stateless)" do
      msg = request("tools/call", 1, %{"name" => "echo", "arguments" => %{"text" => "hello"}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result == %{content: [%{type: "text", text: "hello"}]}
    end

    test "dispatches to arity-2 callback with assigns" do
      msg = request("tools/call", 1, %{"name" => "greet", "arguments" => %{"name" => "Tito"}})
      assigns = %{greeting_prefix: "Hey"}

      assert {:reply, 200, response} = Handler.handle(msg, @handler, assigns)
      assert response.result == %{content: [%{type: "text", text: "Hey, Tito!"}]}
    end

    test "arity-2 callback uses default when no assigns key" do
      msg = request("tools/call", 1, %{"name" => "greet", "arguments" => %{"name" => "World"}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result == %{content: [%{type: "text", text: "Hello, World!"}]}
    end

    test "handles invalid arguments from callback" do
      msg = request("tools/call", 1, %{"name" => "echo", "arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result.isError == true
      assert [%{type: "text", text: "Invalid arguments"}] = response.result.content
    end

    test "catches exceptions and returns isError" do
      msg = request("tools/call", 1, %{"name" => "crash", "arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result.isError == true
      [%{type: "text", text: text}] = response.result.content
      assert text =~ "Failed to call tool"
      assert text =~ "intentional crash"
    end

    test "returns error for unknown tool" do
      msg = request("tools/call", 1, %{"name" => "nonexistent", "arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_602
      assert response.error.data == %{name: "nonexistent"}
    end

    test "returns error when name parameter missing" do
      msg = request("tools/call", 1, %{"arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "name"
    end

    test "defaults arguments to empty map when omitted" do
      msg = request("tools/call", 1, %{"name" => "echo"})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      # echo/1 with empty map returns {:error, :invalid_arguments}
      assert response.result.isError == true
    end

    test "handles unexpected return values from callbacks" do
      msg = request("tools/call", 1, %{"name" => "bad_return", "arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result.isError == true
      [%{type: "text", text: text}] = response.result.content
      assert text =~ "Unexpected tool result"
      assert text =~ "not_found"
    end

    test "passes through pre-formatted map from {:ok, map} callback" do
      msg = request("tools/call", 1, %{"name" => "structured", "arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result == %{content: [%{type: "text", text: "structured"}]}
    end

    test "wraps text with _meta from {:ok, text, metadata} callback" do
      msg = request("tools/call", 1, %{"name" => "with_meta", "arguments" => %{"text" => "hello"}})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result.content == [%{type: "text", text: "hello"}]
      assert response.result._meta == %{request_id: "abc-123"}
    end
  end

  describe "capability advertisement" do
    test "does not advertise resources when handler only implements resources/0" do
      msg = request("initialize", 1, %{"protocolVersion" => "2025-03-26"})

      assert {:reply, 200, response} = Handler.handle(msg, ApiToolkit.TestMCPHandlerResourcesOnly)
      refute Map.has_key?(response.result.capabilities, :resources)
    end

    test "does not advertise prompts when handler only implements prompts/0" do
      msg = request("initialize", 1, %{"protocolVersion" => "2025-03-26"})

      assert {:reply, 200, response} = Handler.handle(msg, ApiToolkit.TestMCPHandlerPromptsOnly)
      refute Map.has_key?(response.result.capabilities, :prompts)
    end

    test "resources/list still works when capability not advertised" do
      msg = request("resources/list", 1)

      assert {:reply, 200, response} = Handler.handle(msg, ApiToolkit.TestMCPHandlerResourcesOnly)
      assert length(response.result.resources) == 1
    end

    test "prompts/list still works when capability not advertised" do
      msg = request("prompts/list", 1)

      assert {:reply, 200, response} = Handler.handle(msg, ApiToolkit.TestMCPHandlerPromptsOnly)
      assert length(response.result.prompts) == 1
    end
  end

  describe "resources/list" do
    test "returns empty list when handler doesn't implement resources" do
      msg = request("resources/list", 1)

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result == %{resources: []}
    end
  end

  describe "resources/read" do
    test "returns error when handler doesn't implement read_resource" do
      msg = request("resources/read", 1, %{"uri" => "test://foo"})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_601
      assert response.error.message =~ "not supported"
    end

    test "returns error when uri parameter missing" do
      msg = request("resources/read", 1, %{})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "uri"
    end
  end

  describe "prompts/list" do
    test "returns empty list when handler doesn't implement prompts" do
      msg = request("prompts/list", 1)

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.result == %{prompts: []}
    end
  end

  describe "prompts/get" do
    test "returns error when handler doesn't implement get_prompt" do
      msg = request("prompts/get", 1, %{"name" => "test"})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_601
      assert response.error.message =~ "not supported"
    end

    test "returns error when name parameter missing" do
      msg = request("prompts/get", 1, %{})

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "name"
    end
  end

  # --- Full handler tests (TestMCPHandlerFull) ---
  # Verifies success paths for resources/read and prompts/get.

  @full_handler ApiToolkit.TestMCPHandlerFull

  describe "initialize with full handler" do
    test "advertises resources capability when both callbacks exist" do
      msg = request("initialize", 1, %{"protocolVersion" => "2025-03-26"})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert %{resources: %{listChanged: false}} = response.result.capabilities
    end

    test "advertises prompts capability when both callbacks exist" do
      msg = request("initialize", 1, %{"protocolVersion" => "2025-03-26"})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert %{prompts: %{listChanged: false}} = response.result.capabilities
    end
  end

  describe "resources/list with full handler" do
    test "returns all resources" do
      msg = request("resources/list", 1)

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      resources = response.result.resources
      assert length(resources) == 2

      uris = Enum.map(resources, & &1.uri)
      assert "api:///openapi.json" in uris
      assert "api:///readme" in uris
    end
  end

  describe "resources/read with full handler" do
    test "returns content for valid URI" do
      msg = request("resources/read", 1, %{"uri" => "api:///openapi.json"})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert [%{uri: "api:///openapi.json", text: text}] = response.result.contents
      assert text =~ "3.1.0"
    end

    test "returns different content for different URI" do
      msg = request("resources/read", 1, %{"uri" => "api:///readme"})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert [%{uri: "api:///readme", text: text}] = response.result.contents
      assert text =~ "ApiToolkit"
    end

    test "returns error for unknown URI" do
      msg = request("resources/read", 1, %{"uri" => "api:///nonexistent"})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "not found"
    end

    test "returns error when uri parameter missing" do
      msg = request("resources/read", 1, %{})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "uri"
    end
  end

  describe "prompts/list with full handler" do
    test "returns all prompts" do
      msg = request("prompts/list", 1)

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      prompts = response.result.prompts
      assert length(prompts) == 2

      names = Enum.map(prompts, & &1.name)
      assert "search_help" in names
      assert "greeting" in names
    end
  end

  describe "prompts/get with full handler" do
    test "returns message for prompt with arguments" do
      msg = request("prompts/get", 1, %{"name" => "search_help", "arguments" => %{"topic" => "hex"}})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert [%{role: "user", content: %{type: "text", text: text}}] = response.result.messages
      assert text =~ "hex"
      assert text =~ "search"
    end

    test "returns error when required argument missing" do
      msg = request("prompts/get", 1, %{"name" => "search_help", "arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "topic"
    end

    test "returns message for no-argument prompt" do
      msg = request("prompts/get", 1, %{"name" => "greeting"})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert [%{role: "user", content: %{type: "text", text: text}}] = response.result.messages
      assert text =~ "Hello"
    end

    test "returns error for unknown prompt" do
      msg = request("prompts/get", 1, %{"name" => "nonexistent"})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "not found"
    end

    test "returns error when name parameter missing" do
      msg = request("prompts/get", 1, %{})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert response.error.code == -32_602
      assert response.error.message =~ "name"
    end

    test "defaults arguments to empty map when omitted" do
      msg = request("prompts/get", 1, %{"name" => "greeting"})

      assert {:reply, 200, response} = Handler.handle(msg, @full_handler)
      assert is_list(response.result.messages)
    end
  end

  # --- Exception safety tests ---
  # Verifies that raising :read / :handler functions produce MCP error responses
  # instead of crashing the process (matching tools/call behavior).

  defmodule RaisingMCPHandler do
    @moduledoc false
    @behaviour ApiToolkit.MCP.Server

    @impl true
    def server_info, do: %{name: "raising-handler", version: "0.1.0"}

    @impl true
    def tools, do: []

    @impl true
    def resources do
      [%{uri: "api:///boom", name: "boom", description: "Raises", mimeType: "text/plain"}]
    end

    @impl true
    def read_resource("api:///boom"), do: raise("kaboom!")
    def read_resource(_uri), do: {:error, "Resource not found"}

    @impl true
    def prompts do
      [%{name: "explode", description: "Raises", arguments: []}]
    end

    @impl true
    def get_prompt("explode", _args), do: raise("prompt explosion!")
    def get_prompt(_name, _args), do: {:error, "Prompt not found"}
  end

  describe "resources/read exception safety" do
    test "returns MCP error when read_resource raises" do
      msg = request("resources/read", 1, %{"uri" => "api:///boom"})

      assert {:reply, 200, response} = Handler.handle(msg, RaisingMCPHandler)
      assert response.error.code == -32_602
      assert response.error.message =~ "kaboom!"
    end
  end

  describe "prompts/get exception safety" do
    test "returns MCP error when get_prompt raises" do
      msg = request("prompts/get", 1, %{"name" => "explode"})

      assert {:reply, 200, response} = Handler.handle(msg, RaisingMCPHandler)
      assert response.error.code == -32_602
      assert response.error.message =~ "prompt explosion!"
    end
  end

  describe "notifications" do
    test "initialized returns 202 with nil body" do
      msg = notification("notifications/initialized")

      assert {:reply, 202, nil} = Handler.handle(msg, @handler)
    end

    test "cancelled returns 202 with nil body" do
      msg = notification("notifications/cancelled")

      assert {:reply, 202, nil} = Handler.handle(msg, @handler)
    end

    test "unknown notification returns 202" do
      msg = notification("notifications/unknown")

      assert {:reply, 202, nil} = Handler.handle(msg, @handler)
    end
  end

  describe "unknown method" do
    test "returns method not found error" do
      msg = request("unknown/method", 1)

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_601
      assert response.error.data == %{method: "unknown/method"}
    end
  end

  describe "JSON-RPC validation" do
    test "rejects message without jsonrpc field" do
      msg = %{"method" => "ping", "id" => 1}

      assert {:error, 400, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_600
    end

    test "rejects message with wrong jsonrpc version" do
      msg = %{"jsonrpc" => "1.0", "method" => "ping", "id" => 1}

      assert {:error, 400, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_600
    end

    test "rejects message without method" do
      msg = %{"jsonrpc" => "2.0", "id" => 1}

      assert {:error, 400, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_600
    end

    test "accepts string request IDs" do
      msg = %{"jsonrpc" => "2.0", "method" => "ping", "id" => "abc-123"}

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      assert response.id == "abc-123"
    end

    test "rejects non-string non-number request IDs" do
      msg = %{"jsonrpc" => "2.0", "method" => "ping", "id" => [1, 2]}

      assert {:error, 400, response} = Handler.handle(msg, @handler)
      assert response.error.code == -32_600
    end

    test "coerces non-map params to empty map" do
      msg = request("initialize", 1, "bad")

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      # params coerced to %{}, so protocolVersion is nil → missing param error
      assert response.error.code == -32_602
      assert response.error.message =~ "protocolVersion"
    end

    test "coerces array params to empty map" do
      msg = request("tools/call", 1, [1, 2, 3])

      assert {:reply, 200, response} = Handler.handle(msg, @handler)
      # params coerced to %{}, missing "name" → error
      assert response.error.code == -32_602
      assert response.error.message =~ "name"
    end
  end

  describe "handle_batch" do
    test "processes multiple requests and returns array of responses" do
      messages = [
        request("ping", 1),
        request("ping", 2)
      ]

      assert {:reply, 200, responses} = Handler.handle_batch(messages, @handler, %{})
      assert length(responses) == 2
      assert Enum.all?(responses, &(&1.result == %{}))
      ids = Enum.map(responses, & &1.id)
      assert ids == [1, 2]
    end

    test "omits responses for notifications" do
      messages = [
        request("ping", 1),
        notification("notifications/initialized"),
        request("ping", 2)
      ]

      assert {:reply, 200, responses} = Handler.handle_batch(messages, @handler, %{})
      assert length(responses) == 2
    end

    test "returns 202 when all messages are notifications" do
      messages = [
        notification("notifications/initialized"),
        notification("notifications/cancelled")
      ]

      assert {:reply, 202, nil} = Handler.handle_batch(messages, @handler, %{})
    end

    test "rejects empty array" do
      assert {:error, 400, response} = Handler.handle_batch([], @handler, %{})
      assert response.error.code == -32_600
      assert response.error.message =~ "empty batch"
    end

    test "handles mixed valid and invalid messages" do
      messages = [
        request("ping", 1),
        %{"not" => "valid"}
      ]

      assert {:reply, 200, responses} = Handler.handle_batch(messages, @handler, %{})
      assert length(responses) == 2

      [ping_resp, error_resp] = responses
      assert ping_resp.result == %{}
      assert error_resp.error.code == -32_600
    end

    test "rejects initialize inside a batch" do
      messages = [
        request("initialize", 1, %{"protocolVersion" => "2025-03-26"}),
        request("ping", 2)
      ]

      assert {:error, 400, response} = Handler.handle_batch(messages, @handler, %{})
      assert response.error.code == -32_600
      assert response.error.message =~ "initialize must not be part of a batch"
    end

    test "rejects initialize anywhere in a batch" do
      messages = [
        request("ping", 1),
        request("initialize", 2, %{"protocolVersion" => "2025-03-26"})
      ]

      assert {:error, 400, response} = Handler.handle_batch(messages, @handler, %{})
      assert response.error.code == -32_600
      assert response.error.message =~ "initialize"
    end
  end
end
