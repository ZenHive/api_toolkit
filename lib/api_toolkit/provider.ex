defmodule ApiToolkit.Provider do
  @moduledoc """
  Behaviour and macros for defining API providers with auto-generated discovery.

  Using this module generates both the endpoint functions AND discovery metadata
  from a single source of truth, ensuring documentation never becomes stale.

  ## Usage

      defmodule MyProvider do
        use ApiToolkit.Provider,
          name: "My API",
          description: "Description of the API",
          rate_limit: "1 req/sec",
          cache_ttl_ms: 300_000

        defapi :my_endpoint,
          path: "/my/endpoint",
          description: "What this endpoint does",
          params: [
            %{name: "query", type: :string, required: true, description: "Search query"}
          ]
      end

  This generates:
  - `my_endpoint/1` function that you implement
  - `endpoints/0` listing all defined endpoints
  - `describe/1` for detailed endpoint info
  - `provider_info/0` with provider metadata
  """

  @type param :: %{
          name: String.t(),
          type: :string | :integer | :float,
          required: boolean(),
          description: String.t(),
          example: String.t() | nil,
          values: [String.t()] | nil
        }

  @type endpoint :: %{
          function: atom(),
          path: String.t(),
          method: :get | :post,
          description: String.t(),
          params: [param()],
          errors: [atom()],
          categories: [atom()] | nil
        }

  @type provider_info :: %{
          name: String.t(),
          description: String.t(),
          rate_limit: String.t() | nil,
          cache_ttl_ms: pos_integer()
        }

  @doc "Returns all endpoint metadata for this provider."
  @callback endpoints() :: [endpoint()]

  @doc "Returns metadata about this provider (name, description, rate limit, TTL)."
  @callback provider_info() :: provider_info()

  @doc "Returns metadata for a specific endpoint by name, or nil if not found."
  @callback describe(atom()) :: endpoint() | nil

  @doc """
  Gets TTL from env var or falls back to default.

  Env var format: `{PROVIDER_NAME}_CACHE_TTL_MS` (e.g., BRAVE_CACHE_TTL_MS)
  """
  @spec runtime_ttl(String.t(), pos_integer()) :: pos_integer()
  def runtime_ttl(provider_name, default_ttl) do
    env_var = "#{provider_name}_CACHE_TTL_MS"

    case System.get_env(env_var) do
      nil ->
        default_ttl

      value ->
        case Integer.parse(value) do
          {ttl, ""} when ttl > 0 -> ttl
          _ -> default_ttl
        end
    end
  end

  @doc "Sets up the provider behaviour, imports `defapi/2`, and registers the `@before_compile` hook."
  defmacro __using__(opts) do
    quote do
      @behaviour ApiToolkit.Provider

      import ApiToolkit.Provider, only: [defapi: 2]

      # Store provider info from use options
      @provider_opts unquote(opts)

      # Accumulator for endpoint definitions
      Module.register_attribute(__MODULE__, :endpoint_defs, accumulate: true)

      @before_compile ApiToolkit.Provider
    end
  end

  @doc """
  Defines an API endpoint with metadata for discovery.

  ## Options

  - `:path` - The HTTP path for this endpoint (required)
  - `:method` - HTTP method, defaults to `:get`
  - `:description` - Human-readable description (required)
  - `:params` - List of parameter maps with name, type, required, description
  - `:errors` - List of possible error atoms
  - `:categories` - List of category atoms for grouping

  ## Example

      defapi :search,
        path: "/brave/search",
        description: "Search the web using Brave Search",
        params: [
          %{name: "q", type: :string, required: true, description: "Search query"}
        ],
        errors: [:invalid_params, :rate_limited, :upstream_error]
  """
  defmacro defapi(name, opts) do
    quote do
      @endpoint_defs {unquote(name), unquote(opts)}
    end
  end

  @doc "Generates `provider_info/0`, `endpoints/0`, `describe/1`, and `indicators/0` from accumulated `defapi` definitions."
  defmacro __before_compile__(env) do
    endpoint_defs = env.module |> Module.get_attribute(:endpoint_defs) |> Enum.reverse()
    provider_opts = Module.get_attribute(env.module, :provider_opts)

    provider_info = build_provider_info(provider_opts)
    endpoints_data = build_endpoints_list(endpoint_defs)

    # Derive provider name for env var lookup (e.g., MyApp.Providers.Brave -> "BRAVE")
    provider_env_name =
      env.module
      |> Module.split()
      |> List.last()
      |> String.upcase()

    default_ttl = provider_info.cache_ttl_ms

    # Generate provider_info/0 with runtime TTL lookup
    provider_info_fn =
      quote do
        @impl ApiToolkit.Provider
        @doc "Returns metadata about this provider."
        @spec provider_info() :: ApiToolkit.Provider.provider_info()
        def provider_info do
          %{
            name: unquote(provider_info.name),
            description: unquote(provider_info.description),
            rate_limit: unquote(provider_info.rate_limit),
            cache_ttl_ms: ApiToolkit.Provider.runtime_ttl(unquote(provider_env_name), unquote(default_ttl))
          }
        end
      end

    # Generate endpoints/0
    endpoints_fn =
      quote do
        @impl ApiToolkit.Provider
        @doc "Returns list of all endpoints with their metadata."
        @spec endpoints() :: [ApiToolkit.Provider.endpoint()]
        def endpoints do
          unquote(Macro.escape(endpoints_data))
        end
      end

    # Generate describe/1 for each endpoint
    describe_fns =
      for {name, opts} <- endpoint_defs do
        endpoint_meta = build_endpoint_meta(name, opts)

        quote do
          @impl ApiToolkit.Provider
          def describe(unquote(name)) do
            unquote(Macro.escape(endpoint_meta))
          end
        end
      end

    # Generate catch-all describe/1
    describe_fallback =
      quote do
        @impl ApiToolkit.Provider
        @doc "Returns detailed metadata for a specific endpoint."
        @spec describe(atom()) :: ApiToolkit.Provider.endpoint() | nil
        def describe(_), do: nil
      end

    # Generate indicators/0 for backwards compatibility with router generation
    indicators_fn =
      quote do
        @doc "Returns list of endpoint names and descriptions (for router generation)."
        @spec indicators() :: [{atom(), String.t()}]
        def indicators do
          Enum.map(endpoints(), fn ep -> {ep.function, ep.description} end)
        end
      end

    [provider_info_fn, endpoints_fn] ++ describe_fns ++ [describe_fallback, indicators_fn]
  end

  @doc """
  Extracts provider metadata from `use ApiToolkit.Provider` options.

  Called at compile time by `__before_compile__/1` to build the provider info map.
  """
  @spec build_provider_info(keyword()) :: provider_info()
  def build_provider_info(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      rate_limit: Keyword.get(opts, :rate_limit),
      cache_ttl_ms: Keyword.fetch!(opts, :cache_ttl_ms)
    }
  end

  @doc """
  Converts accumulated endpoint definitions into a list of endpoint metadata maps.

  Called at compile time by `__before_compile__/1` to build the endpoints list.
  """
  @spec build_endpoints_list([{atom(), keyword()}]) :: [endpoint()]
  def build_endpoints_list(endpoint_defs) do
    Enum.map(endpoint_defs, fn {name, opts} ->
      build_endpoint_meta(name, opts)
    end)
  end

  @doc """
  Builds a single endpoint metadata map from a `defapi` name and options.

  Called at compile time by `build_endpoints_list/1` and `__before_compile__/1`.
  """
  @spec build_endpoint_meta(atom(), keyword()) :: endpoint()
  def build_endpoint_meta(name, opts) do
    %{
      function: name,
      path: Keyword.fetch!(opts, :path),
      method: Keyword.get(opts, :method, :get),
      description: Keyword.fetch!(opts, :description),
      params: Keyword.get(opts, :params, []),
      errors: Keyword.get(opts, :errors, [:invalid_params, :not_found, :rate_limited, :upstream_error]),
      categories: Keyword.get(opts, :categories)
    }
  end
end
