defmodule ApiToolkit.Discovery do
  @moduledoc """
  Generates discovery functions for API providers.

  Provides a `use` macro that generates 8 discovery functions based on
  a list of provider modules implementing `ApiToolkit.Provider`.

  ## Usage

      defmodule MyApp.Discovery do
        use ApiToolkit.Discovery,
          providers: [
            MyApp.Providers.ServiceA,
            MyApp.Providers.ServiceB
          ]
      end

  This generates:
  - `providers/0` - List all providers with metadata
  - `all_endpoints/0` - Flat list of all endpoints across providers
  - `describe/1` - Look up endpoint by path
  - `help/0` - Compact help string for LLMs
  - `by_provider/0` - Endpoints grouped by provider name
  - `search/1` - Search endpoints by keyword
  - `categories/0` - All unique categories sorted
  - `by_category/1` - Endpoints matching a category
  """

  defmacro __using__(opts) do
    providers = Keyword.fetch!(opts, :providers)

    quote do
      @moduledoc """
      Central discovery for all API endpoints.

      LLMs can call these functions to understand available capabilities.
      All metadata is generated from the same source that defines the endpoints,
      ensuring documentation never becomes stale.
      """

      @providers unquote(providers)

      @typedoc "Provider info including module reference"
      @type provider_info :: %{
              name: String.t(),
              description: String.t(),
              rate_limit: String.t() | nil,
              cache_ttl_ms: pos_integer(),
              module: module()
            }

      @typedoc "Endpoint info including provider name"
      @type endpoint_info :: %{
              function: atom(),
              path: String.t(),
              method: :get | :post,
              description: String.t(),
              params: [map()],
              errors: [atom()],
              provider: String.t(),
              categories: [atom()] | nil
            }

      @doc """
      Lists all available providers with their info.

      Returns a list of maps containing:
      - `name` - Human-readable provider name
      - `description` - What the provider does
      - `rate_limit` - Rate limiting info (if any)
      - `cache_ttl_ms` - How long responses are cached
      - `module` - The Elixir module implementing the provider
      """
      @spec providers() :: [provider_info()]
      def providers do
        Enum.map(@providers, fn mod ->
          Map.put(mod.provider_info(), :module, mod)
        end)
      end

      @doc """
      Lists all endpoints across all providers.

      Returns a flat list of all endpoints with their metadata,
      including which provider they belong to.
      """
      @spec all_endpoints() :: [endpoint_info()]
      def all_endpoints do
        Enum.flat_map(@providers, fn mod ->
          provider_name = mod.provider_info().name

          Enum.map(mod.endpoints(), fn endpoint ->
            Map.put(endpoint, :provider, provider_name)
          end)
        end)
      end

      @doc """
      Describes a specific endpoint by path.

      Returns the endpoint metadata or nil if not found.
      """
      @spec describe(String.t()) :: endpoint_info() | nil
      def describe(path) do
        Enum.find(all_endpoints(), &(&1.path == path))
      end

      @doc """
      Returns a compact help string for LLMs.

      Provides a quick overview of all available endpoints
      with their paths and descriptions.
      """
      @spec help() :: String.t()
      def help do
        endpoint_lines =
          Enum.map_join(all_endpoints(), "\n", fn ep -> "  #{ep.path} - #{ep.description}" end)

        """
        Available API Endpoints:

        #{endpoint_lines}

        Call `#{inspect(__MODULE__)}.describe("/path")` for detailed parameter info.
        """
      end

      @doc """
      Returns endpoints grouped by provider.

      Useful for understanding the API surface area by category.
      """
      @spec by_provider() :: %{String.t() => [endpoint_info()]}
      def by_provider do
        Enum.group_by(all_endpoints(), & &1.provider)
      end

      @doc """
      Searches endpoints by keyword in path or description.

      Case-insensitive search across endpoint paths and descriptions.
      """
      @spec search(String.t()) :: [endpoint_info()]
      def search(keyword) do
        keyword_lower = String.downcase(keyword)

        Enum.filter(all_endpoints(), fn ep ->
          String.contains?(String.downcase(ep.path), keyword_lower) or
            String.contains?(String.downcase(ep.description), keyword_lower)
        end)
      end

      @doc """
      Lists all unique categories across all providers.

      Returns a sorted list of category atoms used by any endpoint.
      """
      @spec categories() :: [atom()]
      def categories do
        all_endpoints()
        |> Enum.flat_map(fn ep -> ep[:categories] || [] end)
        |> Enum.uniq()
        |> Enum.sort()
      end

      @doc """
      Returns endpoints matching a specific category.

      Filters endpoints that have the given category in their categories list.
      """
      @spec by_category(atom()) :: [endpoint_info()]
      def by_category(category) when is_atom(category) do
        Enum.filter(all_endpoints(), fn ep ->
          categories = ep[:categories] || []
          category in categories
        end)
      end
    end
  end
end
