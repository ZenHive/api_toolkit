defmodule ApiToolkit.MCP do
  @moduledoc """
  Macro for generating MCP server handlers from Discovery metadata.

  Converts all `defapi`-declared endpoints in a Discovery module into MCP tool
  definitions automatically — zero boilerplate for consumers.

  ## Usage

      defmodule MyApp.MCPHandler do
        use ApiToolkit.MCP,
          discovery: MyApp.Discovery,
          server_info: %{name: "my-app", version: "1.0.0"}
      end

  This generates an `ApiToolkit.MCP.Server` implementation with:

  - `tools/0` — MCP tool definitions built from all Discovery endpoints
  - `server_info/0` — server identity for the `initialize` response
  - `dispatch_map/0` — `%{tool_name => {module, function, tier}}` (for T3 payment layer)

  ## Options

  - `:discovery` (required) — module using `ApiToolkit.Discovery`
  - `:server_info` (required) — `%{name: String.t(), version: String.t()}`
  - `:strip_prefixes` — path segments to strip from tool names (default: `["api"]`)
  - `:tool_name` — custom `(endpoint -> String.t())` naming function
  - `:tiers` — `%{module => :free | :paid}` tier assignments (default: all `:free`)
  - `:resources` — list of resource definitions (see Resource Registration below)
  - `:prompts` — list of prompt definitions (see Prompt Registration below)

  ## Tool Naming

  By default, tool names are derived from endpoint paths:

      /api/hex/encode  → "hex_encode"
      /test/search     → "test_search"

  Override with a custom function:

      use ApiToolkit.MCP,
        discovery: MyApp.Discovery,
        server_info: %{name: "my-app", version: "1.0.0"},
        tool_name: fn ep -> "myprefix_\#{ep.function}" end

  ## Resource Registration

  Declare MCP resources with a `:read` function that returns the content at runtime:

      use ApiToolkit.MCP,
        discovery: MyApp.Discovery,
        server_info: %{name: "my-app", version: "1.0.0"},
        resources: [
          %{uri: "api:///openapi.json", name: "openapi", description: "OpenAPI spec",
            mimeType: "application/json", read: fn -> JSON.encode!(%{openapi: "3.1.0"}) end},
          %{uri: "api:///readme", name: "readme", mimeType: "text/plain",
            read: fn -> File.read!("README.md") end}
        ]

  Generates `resources/0` (metadata without `:read`) and `read_resource/1`
  (dispatches by URI to the corresponding `:read` function). Unknown URIs
  return `{:error, "Resource not found"}`.

  ## Prompt Registration

  Declare MCP prompts with a `:handler` function that receives arguments and
  returns `{:ok, text}` or `{:error, reason}`:

      use ApiToolkit.MCP,
        discovery: MyApp.Discovery,
        server_info: %{name: "my-app", version: "1.0.0"},
        prompts: [
          %{name: "help", description: "Usage help", arguments: [],
            handler: fn _args -> {:ok, "Try the search tool"} end},
          %{name: "search", description: "Search guidance",
            arguments: [%{name: "topic", required: true, description: "Topic"}],
            handler: fn %{"topic" => t} -> {:ok, "Search for \#{t}"} end}
        ]

  Generates `prompts/0` (metadata without `:handler`) and `get_prompt/2`
  (dispatches by name to the corresponding `:handler` function). Unknown
  prompt names return `{:error, "Prompt not found"}`.

  ## Wiring to Plug

  Forward requests to `ApiToolkit.MCP.Plug`:

      forward "/mcp", to: ApiToolkit.MCP.Plug, init_opts: [handler: MyApp.MCPHandler]
  """

  defmacro __using__(opts) do
    discovery = Keyword.fetch!(opts, :discovery)
    server_info = Keyword.fetch!(opts, :server_info)
    resources = Keyword.get(opts, :resources)
    prompts = Keyword.get(opts, :prompts)

    # ToolBuilder options (strip_prefixes, tool_name, tiers)
    builder_opts = Keyword.drop(opts, [:discovery, :server_info, :resources, :prompts])
    tool_builder = ApiToolkit.MCP.ToolBuilder

    # Resource and prompt functions are generated directly inside the quote
    # block. The key challenge: anonymous functions (:read, :handler) can't
    # be Macro.escape'd or stored in module attributes for injection into AST.
    #
    # Solution: define private functions (__mcp_resources__/0, __mcp_prompts__/0)
    # that return the raw lists WITH their anonymous functions. These are
    # generated via `unquote(resources)` which evaluates to real maps at the
    # caller's compile time. The public callbacks call these private functions
    # and do runtime lookup — O(n) over a small list (typically <10 items).
    resource_ast =
      if resources do
        quote do
          @doc false
          defp __mcp_resources__, do: unquote(resources)

          @impl ApiToolkit.MCP.Server
          @doc "Returns registered MCP resources."
          def resources do
            Enum.map(__mcp_resources__(), &Map.delete(&1, :read))
          end

          @impl ApiToolkit.MCP.Server
          @doc false
          def read_resource(uri) do
            case Enum.find(__mcp_resources__(), &(&1.uri == uri)) do
              %{read: reader} -> {:ok, reader.()}
              nil -> {:error, "Resource not found"}
            end
          end
        end
      end

    prompt_ast =
      if prompts do
        quote do
          @doc false
          defp __mcp_prompts__, do: unquote(prompts)

          @impl ApiToolkit.MCP.Server
          @doc "Returns registered MCP prompts."
          def prompts do
            Enum.map(__mcp_prompts__(), &Map.delete(&1, :handler))
          end

          @impl ApiToolkit.MCP.Server
          @doc false
          def get_prompt(name, args) do
            case Enum.find(__mcp_prompts__(), &(&1.name == name)) do
              %{handler: handler} -> handler.(args)
              nil -> {:error, "Prompt not found"}
            end
          end
        end
      end

    quote do
      @behaviour ApiToolkit.MCP.Server

      @impl ApiToolkit.MCP.Server
      @doc "Returns MCP tool definitions built from Discovery endpoints."
      def tools do
        unquote(tool_builder).build_tools(unquote(discovery), unquote(builder_opts))
      end

      @impl ApiToolkit.MCP.Server
      @doc "Returns server name and version for the MCP `initialize` response."
      def server_info, do: unquote(server_info)

      @doc "Returns dispatch map linking tool names to `{module, function, tier}` tuples."
      @spec dispatch_map() :: %{String.t() => {module(), atom(), atom()}}
      def dispatch_map do
        unquote(tool_builder).dispatch_map(unquote(discovery), unquote(builder_opts))
      end

      unquote(resource_ast)
      unquote(prompt_ast)
    end
  end
end
