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

  ## Tool Naming

  By default, tool names are derived from endpoint paths:

      /api/hex/encode  → "hex_encode"
      /test/search     → "test_search"

  Override with a custom function:

      use ApiToolkit.MCP,
        discovery: MyApp.Discovery,
        server_info: %{name: "my-app", version: "1.0.0"},
        tool_name: fn ep -> "myprefix_\#{ep.function}" end

  ## Wiring to Plug

  Forward requests to `ApiToolkit.MCP.Plug`:

      forward "/mcp", to: ApiToolkit.MCP.Plug, init_opts: [handler: MyApp.MCPHandler]
  """

  defmacro __using__(opts) do
    discovery = Keyword.fetch!(opts, :discovery)
    server_info = Keyword.fetch!(opts, :server_info)

    # ToolBuilder options (strip_prefixes, tool_name, tiers)
    # Inlined via unquote into function bodies — NOT stored as module attributes,
    # because anonymous functions (e.g., :tool_name) can't be escaped into @attributes.
    builder_opts = Keyword.drop(opts, [:discovery, :server_info])
    tool_builder = ApiToolkit.MCP.ToolBuilder

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
    end
  end
end
