defmodule ApiToolkit.MCP.ToolBuilderTest do
  use ExUnit.Case, async: true

  alias ApiToolkit.MCP.Handler
  alias ApiToolkit.MCP.ToolBuilder

  describe "build_input_schema/1" do
    test "converts string param with required" do
      params = [%{name: "q", type: :string, required: true, description: "Search query"}]

      assert %{
               type: "object",
               properties: %{"q" => %{type: "string", description: "Search query"}},
               required: ["q"]
             } = ToolBuilder.build_input_schema(params)
    end

    test "converts integer and float types" do
      params = [
        %{name: "count", type: :integer, required: false, description: "Count"},
        %{name: "price", type: :float, required: false, description: "Price"}
      ]

      schema = ToolBuilder.build_input_schema(params)

      assert schema.properties["count"].type == "integer"
      assert schema.properties["price"].type == "number"
      refute Map.has_key?(schema, :required)
    end

    test "includes example as default" do
      params = [%{name: "q", type: :string, required: true, description: "Query", example: "elixir"}]

      schema = ToolBuilder.build_input_schema(params)
      assert schema.properties["q"].default == "elixir"
    end

    test "includes values as enum" do
      params = [%{name: "format", type: :string, required: false, description: "Format", values: ["json", "xml"]}]

      schema = ToolBuilder.build_input_schema(params)
      assert schema.properties["format"].enum == ["json", "xml"]
    end

    test "omits example and values when nil" do
      params = [%{name: "q", type: :string, required: true, description: "Query"}]

      schema = ToolBuilder.build_input_schema(params)
      prop = schema.properties["q"]
      refute Map.has_key?(prop, :default)
      refute Map.has_key?(prop, :enum)
    end

    test "empty params produces empty schema" do
      assert %{type: "object", properties: %{}} = ToolBuilder.build_input_schema([])
    end

    test "multiple required params" do
      params = [
        %{name: "a", type: :string, required: true, description: "A"},
        %{name: "b", type: :string, required: true, description: "B"},
        %{name: "c", type: :string, required: false, description: "C"}
      ]

      schema = ToolBuilder.build_input_schema(params)
      assert Enum.sort(schema.required) == ["a", "b"]
    end
  end

  describe "tool_name_from_path/2" do
    test "strips api prefix by default" do
      assert "hex_encode" = ToolBuilder.tool_name_from_path("/api/hex/encode")
    end

    test "preserves non-api prefix segments" do
      assert "test_search" = ToolBuilder.tool_name_from_path("/test/search")
    end

    test "strips path parameters" do
      assert "test_detail" = ToolBuilder.tool_name_from_path("/test/detail/:id")
    end

    test "custom strip_prefixes" do
      assert "encode" = ToolBuilder.tool_name_from_path("/api/hex/encode", strip_prefixes: ["api", "hex"])
    end

    test "no matching prefix keeps all segments" do
      assert "v1_users_list" = ToolBuilder.tool_name_from_path("/v1/users/list", strip_prefixes: ["api"])
    end

    test "empty path" do
      assert "" = ToolBuilder.tool_name_from_path("/")
    end

    test "only strips matching prefix segments from the beginning" do
      # "api" in the middle should NOT be stripped
      assert "users_api_keys" = ToolBuilder.tool_name_from_path("/api/users/api/keys")
    end
  end

  describe "translate_result/1" do
    test "strips TTL from ok tuple with map" do
      assert {:ok, json} = ToolBuilder.translate_result({:ok, %{results: []}, 300_000})
      assert %{"results" => []} = JSON.decode!(json)
    end

    test "strips TTL from ok tuple with list" do
      assert {:ok, json} = ToolBuilder.translate_result({:ok, [1, 2, 3], 60_000})
      assert [1, 2, 3] = JSON.decode!(json)
    end

    test "encodes map without TTL" do
      assert {:ok, json} = ToolBuilder.translate_result({:ok, %{name: "test"}})
      assert %{"name" => "test"} = JSON.decode!(json)
    end

    test "strips TTL from ok tuple with binary text" do
      assert {:ok, "hello"} = ToolBuilder.translate_result({:ok, "hello", 300_000})
    end

    test "passes through binary text" do
      assert {:ok, "hello"} = ToolBuilder.translate_result({:ok, "hello"})
    end

    test "translates :invalid_params to :invalid_arguments" do
      assert {:error, :invalid_arguments} = ToolBuilder.translate_result({:error, :invalid_params})
    end

    test "converts atom errors to strings" do
      assert {:error, "not_found"} = ToolBuilder.translate_result({:error, :not_found})
    end

    test "passes through string errors" do
      assert {:error, "bad request"} = ToolBuilder.translate_result({:error, "bad request"})
    end

    test "formats three-element error tuples" do
      assert {:error, msg} = ToolBuilder.translate_result({:error, :invalid_params, "missing q"})
      assert msg =~ "invalid_params"
      assert msg =~ "missing q"
    end

    test "handles unexpected results" do
      assert {:error, msg} = ToolBuilder.translate_result(:unexpected)
      assert msg =~ "Unexpected provider result"
    end
  end

  describe "wrap_callback/2" do
    test "wraps provider function and translates result" do
      callback = ToolBuilder.wrap_callback(ApiToolkit.TestProvider, :search)

      assert {:ok, json} = callback.(%{"q" => "test"})
      assert %{"results" => []} = JSON.decode!(json)
    end

    test "translates provider error" do
      callback = ToolBuilder.wrap_callback(ApiToolkit.TestProvider, :search)

      assert {:error, :invalid_arguments} = callback.(%{})
    end
  end

  describe "endpoint_to_tool/3" do
    test "builds complete tool definition" do
      endpoint = %{
        function: :search,
        path: "/test/search",
        method: :get,
        description: "Search endpoint",
        params: [%{name: "q", type: :string, required: true, description: "Search query"}],
        errors: [:invalid_params],
        categories: [:web]
      }

      tool = ToolBuilder.endpoint_to_tool(endpoint, ApiToolkit.TestProvider, strip_prefixes: [])

      assert tool.name == "test_search"
      assert tool.description == "Search endpoint"
      assert %{type: "object", properties: %{"q" => _}} = tool.inputSchema
      assert is_function(tool.callback, 1)
    end

    test "custom tool_name function" do
      endpoint = %{
        function: :search,
        path: "/test/search",
        method: :get,
        description: "Search",
        params: [],
        errors: [],
        categories: nil
      }

      namer = fn ep -> "custom_#{ep.function}" end
      tool = ToolBuilder.endpoint_to_tool(endpoint, ApiToolkit.TestProvider, tool_name: namer)

      assert tool.name == "custom_search"
    end
  end

  describe "build_tools/2" do
    test "converts all Discovery endpoints to tools" do
      tools = ToolBuilder.build_tools(ApiToolkit.TestDiscovery, strip_prefixes: ["test", "other"])

      names = Enum.map(tools, & &1.name)

      # TestProvider: search, detail; OtherTestProvider: list
      assert "search" in names
      assert "detail" in names
      assert "list" in names
      assert length(tools) == 3
    end

    test "each tool has required fields" do
      tools = ToolBuilder.build_tools(ApiToolkit.TestDiscovery)

      for tool <- tools do
        assert Map.has_key?(tool, :name)
        assert Map.has_key?(tool, :description)
        assert Map.has_key?(tool, :inputSchema)
        assert Map.has_key?(tool, :callback)
        assert is_function(tool.callback, 1)
      end
    end

    test "tools are callable through provider functions" do
      tools = ToolBuilder.build_tools(ApiToolkit.TestDiscovery)
      search_tool = Enum.find(tools, &(&1.name =~ "search"))

      assert {:ok, json} = search_tool.callback.(%{"q" => "test"})
      assert %{"results" => []} = JSON.decode!(json)
    end

    test "raises on duplicate tool names" do
      # Both providers have paths that resolve to same name without strip_prefixes
      # TestProvider: /test/search, OtherTestProvider: /other/list
      # With a tool_name fn that always returns the same name, duplicates are forced
      assert_raise ArgumentError, ~r/Duplicate MCP tool names/, fn ->
        ToolBuilder.build_tools(ApiToolkit.TestDiscovery,
          tool_name: fn _ep -> "collision" end
        )
      end
    end
  end

  describe "dispatch_map/2" do
    test "maps tool names to {module, function, tier} tuples" do
      dispatch = ToolBuilder.dispatch_map(ApiToolkit.TestDiscovery, strip_prefixes: ["test", "other"])

      assert {ApiToolkit.TestProvider, :search, :free} = dispatch["search"]
      assert {ApiToolkit.TestProvider, :detail, :free} = dispatch["detail"]
      assert {ApiToolkit.OtherTestProvider, :list, :free} = dispatch["list"]
    end

    test "respects tier configuration" do
      dispatch =
        ToolBuilder.dispatch_map(ApiToolkit.TestDiscovery,
          strip_prefixes: ["test", "other"],
          tiers: %{ApiToolkit.TestProvider => :paid}
        )

      assert {ApiToolkit.TestProvider, :search, :paid} = dispatch["search"]
      assert {ApiToolkit.OtherTestProvider, :list, :free} = dispatch["list"]
    end

    test "raises on duplicate tool names" do
      assert_raise ArgumentError, ~r/Duplicate MCP tool names/, fn ->
        ToolBuilder.dispatch_map(ApiToolkit.TestDiscovery,
          tool_name: fn _ep -> "collision" end
        )
      end
    end
  end

  describe "use ApiToolkit.MCP integration" do
    test "generated handler implements MCP.Server behaviour" do
      handler = ApiToolkit.TestMCPToolsHandler
      Code.ensure_loaded!(handler)

      assert function_exported?(handler, :tools, 0)
      assert function_exported?(handler, :server_info, 0)
      assert function_exported?(handler, :dispatch_map, 0)
    end

    test "server_info returns configured values" do
      assert %{name: "test-tools", version: "0.1.0"} = ApiToolkit.TestMCPToolsHandler.server_info()
    end

    test "tools returns valid MCP tool definitions" do
      tools = ApiToolkit.TestMCPToolsHandler.tools()

      assert length(tools) == 3
      names = Enum.map(tools, & &1.name)
      assert "search" in names
      assert "detail" in names
      assert "list" in names
    end

    test "dispatch_map matches tools" do
      dispatch = ApiToolkit.TestMCPToolsHandler.dispatch_map()
      tools = ApiToolkit.TestMCPToolsHandler.tools()

      for tool <- tools do
        assert Map.has_key?(dispatch, tool.name),
               "dispatch_map missing tool: #{tool.name}"
      end
    end

    test "tools work end-to-end through MCP Handler" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "tools/call",
        "params" => %{
          "name" => "search",
          "arguments" => %{"q" => "elixir"}
        }
      }

      {:reply, 200, response} = Handler.handle(message, ApiToolkit.TestMCPToolsHandler)

      assert response.result.content
      [content] = response.result.content
      assert content.type == "text"
      assert %{"results" => []} = JSON.decode!(content.text)
    end

    test "initialize includes generated tools without callbacks" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "init",
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2025-03-26"}
      }

      {:reply, 200, response} = Handler.handle(message, ApiToolkit.TestMCPToolsHandler)

      tools = response.result.tools
      assert length(tools) == 3

      for tool <- tools do
        refute Map.has_key?(tool, :callback), "callback should be stripped from #{tool.name}"
        assert Map.has_key?(tool, :name)
        assert Map.has_key?(tool, :inputSchema)
      end
    end

    test "error from provider is translated to MCP error" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "2",
        "method" => "tools/call",
        "params" => %{
          "name" => "search",
          "arguments" => %{}
        }
      }

      {:reply, 200, response} = Handler.handle(message, ApiToolkit.TestMCPToolsHandler)

      result = response.result
      assert result.isError == true
    end
  end

  describe "use ApiToolkit.MCP with :resources and :prompts" do
    @rp_handler ApiToolkit.TestMCPResourcesPromptsHandler

    test "generated handler exports resource and prompt callbacks" do
      Code.ensure_loaded!(@rp_handler)

      assert function_exported?(@rp_handler, :resources, 0)
      assert function_exported?(@rp_handler, :read_resource, 1)
      assert function_exported?(@rp_handler, :prompts, 0)
      assert function_exported?(@rp_handler, :get_prompt, 2)
    end

    test "resources/0 returns metadata without :read key" do
      resources = @rp_handler.resources()

      assert length(resources) == 2
      uris = Enum.map(resources, & &1.uri)
      assert "api:///spec.json" in uris
      assert "api:///help.txt" in uris

      for res <- resources do
        refute Map.has_key?(res, :read), "resources/0 should strip :read key"
        assert Map.has_key?(res, :name)
      end
    end

    test "read_resource/1 returns content for valid URI" do
      assert {:ok, text} = @rp_handler.read_resource("api:///spec.json")
      assert text =~ "1.0"
    end

    test "read_resource/1 returns error for unknown URI" do
      assert {:error, "Resource not found"} = @rp_handler.read_resource("api:///unknown")
    end

    test "prompts/0 returns metadata without :handler key" do
      prompts = @rp_handler.prompts()

      assert length(prompts) == 2
      names = Enum.map(prompts, & &1.name)
      assert "search_guide" in names
      assert "welcome" in names

      for p <- prompts do
        refute Map.has_key?(p, :handler), "prompts/0 should strip :handler key"
      end
    end

    test "get_prompt/2 returns ok for valid prompt with arguments" do
      assert {:ok, text} = @rp_handler.get_prompt("search_guide", %{"topic" => "hex"})
      assert text =~ "hex"
    end

    test "get_prompt/2 returns error for missing required argument" do
      assert {:error, msg} = @rp_handler.get_prompt("search_guide", %{})
      assert msg =~ "topic"
    end

    test "get_prompt/2 returns ok for no-argument prompt" do
      assert {:ok, text} = @rp_handler.get_prompt("welcome", %{})
      assert text =~ "Welcome"
    end

    test "get_prompt/2 returns error for unknown prompt" do
      assert {:error, "Prompt not found"} = @rp_handler.get_prompt("nonexistent", %{})
    end

    test "initialize advertises resources and prompts capabilities" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "init",
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2025-03-26"}
      }

      {:reply, 200, response} = Handler.handle(message, @rp_handler)

      assert %{resources: %{listChanged: false}} = response.result.capabilities
      assert %{prompts: %{listChanged: false}} = response.result.capabilities
    end

    test "resources/read works end-to-end through MCP Handler" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "resources/read",
        "params" => %{"uri" => "api:///help.txt"}
      }

      {:reply, 200, response} = Handler.handle(message, @rp_handler)

      [content] = response.result.contents
      assert content.uri == "api:///help.txt"
      assert content.text =~ "search tool"
    end

    test "prompts/get works end-to-end through MCP Handler" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "prompts/get",
        "params" => %{"name" => "welcome"}
      }

      {:reply, 200, response} = Handler.handle(message, @rp_handler)

      [msg] = response.result.messages
      assert msg.role == "user"
      assert msg.content.text =~ "Welcome"
    end

    test "tools still work alongside resources and prompts" do
      tools = @rp_handler.tools()
      assert length(tools) == 3
      assert Enum.any?(tools, &(&1.name == "search"))
    end
  end

  describe "use ApiToolkit.MCP with :tool_name option" do
    test "macro-generated tools use custom naming function" do
      tools = ApiToolkit.TestMCPCustomNameHandler.tools()

      names = Enum.map(tools, & &1.name)
      assert "custom_search" in names
      assert "custom_detail" in names
      assert "custom_list" in names
    end

    test "dispatch_map uses custom names" do
      dispatch = ApiToolkit.TestMCPCustomNameHandler.dispatch_map()

      assert {ApiToolkit.TestProvider, :search, :free} = dispatch["custom_search"]
      assert {ApiToolkit.TestProvider, :detail, :free} = dispatch["custom_detail"]
      assert {ApiToolkit.OtherTestProvider, :list, :free} = dispatch["custom_list"]
    end

    test "custom-named tools work through MCP Handler" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "tools/call",
        "params" => %{
          "name" => "custom_search",
          "arguments" => %{"q" => "elixir"}
        }
      }

      {:reply, 200, response} = Handler.handle(message, ApiToolkit.TestMCPCustomNameHandler)

      [content] = response.result.content
      assert content.type == "text"
      assert %{"results" => []} = JSON.decode!(content.text)
    end
  end
end
