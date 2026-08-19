defmodule ApiToolkit.MCP.Server do
  @moduledoc """
  Behaviour for defining MCP (Model Context Protocol) server handlers.

  Consumers implement this behaviour to register tools, resources, and prompts
  that AI agents can discover and invoke via JSON-RPC 2.0.

  ## Usage

      defmodule MyApp.MCPHandler do
        @behaviour ApiToolkit.MCP.Server

        @impl true
        def server_info, do: %{name: "my-app", version: "1.0.0"}

        @impl true
        def tools do
          [
            %{
              name: "search",
              description: "Search the web",
              inputSchema: %{
                type: "object",
                properties: %{q: %{type: "string", description: "Query"}},
                required: ["q"]
              },
              callback: &search/1
            }
          ]
        end

        defp search(%{"q" => query}), do: {:ok, "Results for: \#{query}"}
      end

  Then wire into your Plug router:

      forward "/mcp", to: ApiToolkit.MCP.Plug, init_opts: [handler: MyApp.MCPHandler]

  ## Tool Callbacks

  Tool callbacks can be arity 1 (stateless) or arity 2 (receives assigns map):

  - `callback.(args)` — stateless, receives only the tool arguments
  - `callback.(args, assigns)` — receives arguments + context from Plug assigns

  Return values:

  - `{:ok, text}` — success with text content
  - `{:ok, map}` — success with structured result
  - `{:ok, text, metadata}` — success with text + `_meta` field
  - `{:error, reason}` — tool error (returned as `isError: true`)

  ## Optional Callbacks

  - `resources/0`, `read_resource/1` — MCP resource support (see T4)
  - `prompts/0`, `get_prompt/2` — MCP prompt templates (see T4)
  - `capabilities/0` — additional server capabilities (see T3 for payment)
  """

  @typedoc "Tool definition with name, description, JSON Schema input, and callback function."
  @type tool :: %{
          name: String.t(),
          description: String.t(),
          inputSchema: map(),
          callback: (map() -> tool_result()) | (map(), map() -> tool_result())
        }

  @typedoc "Return value from a tool callback."
  @type tool_result ::
          {:ok, String.t()}
          | {:ok, map()}
          | {:ok, String.t(), map()}
          | {:error, String.t()}
          | {:error, :invalid_arguments}

  @typedoc "MCP resource definition."
  @type resource :: %{
          uri: String.t(),
          name: String.t(),
          description: String.t() | nil,
          mimeType: String.t() | nil
        }

  @typedoc "MCP prompt template definition."
  @type prompt :: %{
          name: String.t(),
          description: String.t() | nil,
          arguments: [%{name: String.t(), description: String.t() | nil, required: boolean()}]
        }

  @typedoc "Server identity returned by `server_info/0`."
  @type server_info :: %{name: String.t(), version: String.t()}

  # Required callbacks

  @doc "Returns the list of tools this server exposes."
  @callback tools() :: [tool()]

  @doc "Returns server name and version for the `initialize` response."
  @callback server_info() :: server_info()

  # Optional callbacks — extensibility for T3/T4

  @doc "Returns the list of resources this server exposes."
  @callback resources() :: [resource()]

  @doc "Reads a resource by URI."
  @callback read_resource(uri :: String.t()) :: {:ok, String.t()} | {:error, String.t()}

  @doc "Returns the list of prompt templates this server exposes."
  @callback prompts() :: [prompt()]

  @doc "Resolves a prompt template with the given arguments."
  @callback get_prompt(name :: String.t(), arguments :: map()) ::
              {:ok, String.t()} | {:error, String.t()}

  @doc "Returns additional server capabilities merged into the `initialize` response."
  @callback capabilities() :: map()

  @doc "Returns payment config for MCP payment gating, or `nil` if not configured."
  @callback payment_config() :: ApiToolkit.MCP.Payment.Config.t() | nil

  @doc """
  Returns `%{tool_name => {module, function, tier}}` for payment tier lookup.

  Required alongside `payment_config/0`: `ApiToolkit.MCP.Payment` fails closed
  and treats every tool as paid when a handler under a payment config doesn't
  expose its tiers here. `use ApiToolkit.MCP` generates this callback.
  """
  @callback dispatch_map() :: %{String.t() => {module(), atom(), atom()}}

  @optional_callbacks resources: 0,
                      read_resource: 1,
                      prompts: 0,
                      get_prompt: 2,
                      capabilities: 0,
                      payment_config: 0,
                      dispatch_map: 0
end
