defmodule ApiToolkit.MCP.ToolBuilder do
  @moduledoc """
  Converts Provider/Discovery endpoint metadata into MCP tool definitions.

  Pure-function module — no processes, no state. Takes Discovery module metadata
  and returns MCP-compatible tool maps with callbacks that dispatch to Provider
  functions.

  ## Usage

      tools = ApiToolkit.MCP.ToolBuilder.build_tools(MyApp.Discovery)
      dispatch = ApiToolkit.MCP.ToolBuilder.dispatch_map(MyApp.Discovery)

  ## Naming Convention

  Tool names are derived from endpoint paths by default:

      /api/hex/encode  → "hex_encode"
      /test/search     → "test_search"
      /test/detail/:id → "test_detail"

  Configurable via `:strip_prefixes` (default: `["api"]`) or a custom
  `:tool_name` function.
  """

  alias ApiToolkit.MCP.Server

  @type tool_name_fn :: (map() -> String.t())

  @type opts :: [
          strip_prefixes: [String.t()],
          tool_name: tool_name_fn(),
          tiers: %{module() => atom()}
        ]

  @doc """
  Builds MCP tool definitions from all endpoints in a Discovery module.

  Returns a list of `ApiToolkit.MCP.Server.tool()` maps ready for use in
  a `tools/0` callback.

  ## Options

  - `:strip_prefixes` — path segments to strip (default: `["api"]`)
  - `:tool_name` — custom `(endpoint -> String.t())` naming function
  - `:tiers` — `%{module => atom()}` tier assignments (default: all `:free`)
  """
  @spec build_tools(module(), opts()) :: [map()]
  def build_tools(discovery_module, opts \\ []) do
    tools =
      Enum.flat_map(discovery_module.providers(), fn provider ->
        provider_module = provider.module

        Enum.map(provider_module.endpoints(), fn endpoint ->
          endpoint_to_tool(endpoint, provider_module, opts)
        end)
      end)

    validate_unique_names!(Enum.map(tools, & &1.name))
    tools
  end

  @doc """
  Builds a dispatch map linking tool names to `{module, function, tier}` tuples.

  Useful for T3 payment layer — lookup tier by tool name to determine pricing.
  """
  @spec dispatch_map(module(), opts()) :: %{String.t() => {module(), atom(), atom()}}
  def dispatch_map(discovery_module, opts \\ []) do
    tiers = Keyword.get(opts, :tiers, %{})

    entries =
      Enum.flat_map(discovery_module.providers(), fn provider ->
        provider_module = provider.module
        tier = Map.get(tiers, provider_module, :free)

        Enum.map(provider_module.endpoints(), fn endpoint ->
          name = resolve_tool_name(endpoint, opts)
          {name, {provider_module, endpoint.function, tier}}
        end)
      end)

    validate_unique_names!(Enum.map(entries, &elem(&1, 0)))
    Map.new(entries)
  end

  @doc """
  Converts a single Provider endpoint into an MCP tool definition.

  The generated callback wraps `apply(module, function, [args])` with
  result translation from Provider format to MCP format.
  """
  @spec endpoint_to_tool(map(), module(), opts()) :: map()
  def endpoint_to_tool(endpoint, provider_module, opts \\ []) do
    %{
      name: resolve_tool_name(endpoint, opts),
      description: endpoint.description,
      inputSchema: build_input_schema(endpoint.params),
      callback: wrap_callback(provider_module, endpoint.function)
    }
  end

  @doc """
  Converts Provider param definitions to a JSON Schema `inputSchema`.

  ## Examples

      iex> params = [%{name: "q", type: :string, required: true, description: "Query"}]
      iex> ApiToolkit.MCP.ToolBuilder.build_input_schema(params)
      %{
        type: "object",
        properties: %{"q" => %{type: "string", description: "Query"}},
        required: ["q"]
      }
  """
  @spec build_input_schema([map()]) :: map()
  def build_input_schema(params) do
    properties =
      Map.new(params, fn param ->
        prop =
          %{type: type_to_json_schema(param.type), description: param.description}
          |> maybe_put(:default, param[:example])
          |> maybe_put(:enum, param[:values])

        {param.name, prop}
      end)

    required =
      params
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)

    schema = %{type: "object", properties: properties}

    case required do
      [] -> schema
      names -> Map.put(schema, :required, names)
    end
  end

  @doc """
  Derives a tool name from an endpoint path.

  Strips configurable path prefixes (default: `["api"]`) and path parameters
  (segments starting with `:`), then joins remaining segments with `_`.

  ## Examples

      iex> ApiToolkit.MCP.ToolBuilder.tool_name_from_path("/api/hex/encode")
      "hex_encode"

      iex> ApiToolkit.MCP.ToolBuilder.tool_name_from_path("/test/detail/:id")
      "test_detail"
  """
  @spec tool_name_from_path(String.t(), keyword()) :: String.t()
  def tool_name_from_path(path, opts \\ []) do
    strip_prefixes = Keyword.get(opts, :strip_prefixes, ["api"])

    path
    |> String.split("/", trim: true)
    |> Enum.reject(&String.starts_with?(&1, ":"))
    |> strip_prefix_segments(strip_prefixes)
    |> Enum.join("_")
  end

  @doc """
  Wraps a Provider function as an MCP tool callback.

  Translates Provider return values to MCP format:

  - `{:ok, data, _ttl}` → `{:ok, json_string}` (strips cache TTL)
  - `{:ok, data}` when map → `{:ok, json_string}`
  - `{:error, :invalid_params}` → `{:error, :invalid_arguments}`
  - `{:error, atom}` → `{:error, string}`
  - `{:error, reason, detail}` → `{:error, string}`
  """
  @spec wrap_callback(module(), atom()) :: (map() -> Server.tool_result())
  def wrap_callback(provider_module, function) do
    fn args ->
      provider_module
      |> apply(function, [args])
      |> translate_result()
    end
  end

  # Translates Provider results to MCP tool_result format
  @doc false
  @spec translate_result(term()) :: Server.tool_result()
  def translate_result({:ok, data, _ttl}) when is_map(data), do: {:ok, JSON.encode!(data)}
  def translate_result({:ok, data, _ttl}) when is_list(data), do: {:ok, JSON.encode!(data)}
  def translate_result({:ok, text, _ttl}) when is_binary(text), do: {:ok, text}
  def translate_result({:ok, data}) when is_map(data), do: {:ok, JSON.encode!(data)}
  def translate_result({:ok, data}) when is_list(data), do: {:ok, JSON.encode!(data)}
  def translate_result({:ok, text}) when is_binary(text), do: {:ok, text}
  def translate_result({:error, :invalid_params}), do: {:error, :invalid_arguments}
  def translate_result({:error, reason}) when is_atom(reason), do: {:error, Atom.to_string(reason)}
  def translate_result({:error, reason}) when is_binary(reason), do: {:error, reason}

  def translate_result({:error, reason, detail}), do: {:error, "#{reason}: #{inspect(detail)}"}

  def translate_result(other), do: {:error, "Unexpected provider result: #{inspect(other)}"}

  # Resolves tool name from endpoint using custom function or path-based default
  defp resolve_tool_name(endpoint, opts) do
    case Keyword.get(opts, :tool_name) do
      nil -> tool_name_from_path(endpoint.path, opts)
      fun when is_function(fun, 1) -> fun.(endpoint)
    end
  end

  # Strips matching prefix segments from the beginning of a path segment list
  defp strip_prefix_segments([], _prefixes), do: []

  defp strip_prefix_segments([head | tail] = segments, prefixes) do
    if head in prefixes do
      strip_prefix_segments(tail, prefixes)
    else
      segments
    end
  end

  # Maps Provider param types to JSON Schema types
  defp type_to_json_schema(:string), do: "string"
  defp type_to_json_schema(:integer), do: "integer"
  defp type_to_json_schema(:float), do: "number"
  defp type_to_json_schema(:boolean), do: "boolean"
  defp type_to_json_schema(:array), do: "array"
  defp type_to_json_schema(other), do: to_string(other)

  # Raises if any names collide — prevents Handler/dispatch_map disagreement
  defp validate_unique_names!(names) do
    names
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> case do
      [] ->
        :ok

      duplicates ->
        names = Enum.map_join(duplicates, ", ", fn {name, _} -> inspect(name) end)

        raise ArgumentError,
              "Duplicate MCP tool names detected: #{names}. " <>
                "Use :strip_prefixes or :tool_name to disambiguate."
    end
  end

  # Puts a key into a map only if the value is non-nil
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
