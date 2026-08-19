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

  ## Payment Gating (T3)

  Gate paid tools behind MPP payment credentials. Requires `{:mpp, "~> 0.14"}`
  as a dependency — it is optional in `api_toolkit`, so consumers using payment
  gating must declare it themselves.

      use ApiToolkit.MCP,
        discovery: MyApp.Discovery,
        server_info: %{name: "my-app", version: "1.0.0"},
        tiers: %{MyApp.PaidProvider => :paid},
        payment: [
          secret_key: "your-hmac-secret",
          realm: "api.example.com",
          method: MyApp.Payments.Stripe,
          amount: "1000",
          currency: "usd"
        ]

  Generates `capabilities/0` (payment method advertisement for `initialize`)
  and `payment_config/0` (builds `Payment.Config` at runtime). The Plug
  auto-detects `payment_config/0` and injects it into Handler assigns.

  Options are forwarded to `MPP.Mcp.init/1`, so the full `MPP.Plug.init/1`
  option set is available — including `:expires_in`, `:opaque`, `:digest`,
  `:intent`, `:methods` for multi-method pricing, and `:store` for replay
  dedup. Two options are api_toolkit-specific: `:rejections` (an
  `ApiToolkit.Rejections` tracker name) and `:capabilities` (merged into the
  generated `capabilities/0`).

  Replay protection is on by default — a verified credential is single-use.
  The default store is started by the `:mpp` application, so single-node
  deployments need no setup; multi-node deployments without sticky routing
  must configure a shared `:store`. A paid tool that raises or returns an
  error still consumes the credential; see `ApiToolkit.MCP.Payment`.

  ## Wiring to Plug

  Forward requests to `ApiToolkit.MCP.Plug`:

      forward "/mcp", to: ApiToolkit.MCP.Plug, init_opts: [handler: MyApp.MCPHandler]
  """

  defmacro __using__(opts) do
    discovery = Keyword.fetch!(opts, :discovery)
    server_info = Keyword.fetch!(opts, :server_info)
    resources = Keyword.get(opts, :resources)
    prompts = Keyword.get(opts, :prompts)
    payment = Keyword.get(opts, :payment)

    # ToolBuilder options (strip_prefixes, tool_name, tiers)
    builder_opts = Keyword.drop(opts, [:discovery, :server_info, :resources, :prompts, :payment])
    tool_builder = ApiToolkit.MCP.ToolBuilder
    payment_mod = ApiToolkit.MCP.Payment

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

    # Payment gating: generates capabilities/0 and payment_config/0 when
    # :payment option is provided. Payment opts contain module references
    # (e.g., method: MyApp.Stripe) which are atoms — they unquote directly
    # without Macro.escape since atoms are valid AST literals.
    #
    # capabilities/0 deep-merges payment caps with user-provided :capabilities
    # so handlers can advertise both payment and custom capabilities. `payment`
    # here is already AST, so :capabilities unquotes directly too — Macro.escape
    # would wrap the quoted map in another layer and yield a tuple at runtime.
    payment_ast =
      if payment do
        custom_caps = Keyword.get(payment, :capabilities, quote(do: %{}))

        quote do
          @impl ApiToolkit.MCP.Server
          @doc "Returns payment + custom capability advertisement for the MCP `initialize` response."
          def capabilities do
            payment_caps = unquote(payment_mod).capabilities(payment_config())
            custom = unquote(custom_caps)

            Map.merge(custom, payment_caps, fn
              :experimental, c, p when is_map(c) and is_map(p) -> Map.merge(c, p)
              _k, _c, p -> p
            end)
          end

          @impl ApiToolkit.MCP.Server
          @doc "Returns payment config built from `:payment` options."
          @spec payment_config() :: unquote(payment_mod).Config.t()
          def payment_config do
            unquote(payment_mod).init(unquote(payment))
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

      @impl ApiToolkit.MCP.Server
      @doc "Returns dispatch map linking tool names to `{module, function, tier}` tuples."
      @spec dispatch_map() :: %{String.t() => {module(), atom(), atom()}}
      def dispatch_map do
        unquote(tool_builder).dispatch_map(unquote(discovery), unquote(builder_opts))
      end

      unquote(resource_ast)
      unquote(prompt_ast)
      unquote(payment_ast)
    end
  end
end
