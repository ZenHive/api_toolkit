defmodule ApiToolkit.OpenAPI do
  @moduledoc """
  Generates an OpenAPI 3.1 document from Discovery metadata.

  Auto-generated from `defapi` declarations — stays in sync automatically.
  Returns a JSON-serializable map that consumers encode with `Jason.encode!/1`.

  ## Usage

      # Minimal
      ApiToolkit.OpenAPI.render(MyDiscovery, name: "MyAPI", version: "1.0.0")

      # Full — with pricing, contact, and service info
      ApiToolkit.OpenAPI.render(MyDiscovery,
        name: "MyAPI",
        version: "1.0.0",
        description: "Blockchain developer tools API.",
        url: "https://myapi.com",
        contact: %{name: "Support", url: "https://myapi.com/support"},
        license: %{name: "MIT", url: "https://opensource.org/licenses/MIT"},
        categories: ["data", "developer-tools"],
        docs: %{homepage: "https://myapi.com", llms: "https://myapi.com/llms.txt"},
        pricing: fn
          %{tier: :paid} -> %{amount: "100", currency: "USDC", method: "tempo"}
          _ -> nil
        end
      )

  ## Pricing

  Pass `:pricing` with a function that receives an endpoint map and returns
  either `nil` (free) or a map with `:amount`, `:currency`, and `:method` keys.
  Priced endpoints get an `x-payment-info` extension and a 402 response.
  """

  @type discovery_module :: module()

  @type pricing_info :: %{
          amount: String.t(),
          currency: String.t(),
          method: String.t()
        }

  @type option ::
          {:name, String.t()}
          | {:version, String.t()}
          | {:description, String.t()}
          | {:url, String.t()}
          | {:contact, map()}
          | {:license, map()}
          | {:categories, [String.t()]}
          | {:docs, map()}
          | {:pricing, (map() -> pricing_info() | nil)}

  @doc """
  Renders an OpenAPI 3.1 document as a JSON-serializable map.

  Requires a Discovery module and options with at least `:name` and `:version`.
  """
  @spec render(discovery_module(), [option()]) :: map()
  def render(discovery_module, opts) do
    name = Keyword.fetch!(opts, :name)
    version = Keyword.fetch!(opts, :version)
    pricing_fn = Keyword.get(opts, :pricing)

    endpoints = discovery_module.all_endpoints()

    doc = %{
      "openapi" => "3.1.0",
      "info" => build_info(name, version, opts),
      "paths" => build_paths(endpoints, pricing_fn)
    }

    doc = maybe_add_servers(doc, Keyword.get(opts, :url))
    maybe_add_service_info(doc, opts)
  end

  # Builds the info object with optional description, contact, and license
  defp build_info(name, version, opts) do
    info = %{"title" => name, "version" => version}
    info = maybe_put(info, "description", Keyword.get(opts, :description))
    info = maybe_put_map(info, "contact", Keyword.get(opts, :contact))
    maybe_put_map(info, "license", Keyword.get(opts, :license))
  end

  # Builds the paths object — groups endpoints by path, then by method
  defp build_paths(endpoints, pricing_fn) do
    endpoints
    |> Enum.group_by(& &1.path)
    |> Map.new(fn {path, group} ->
      methods =
        Map.new(group, fn endpoint ->
          method = Atom.to_string(endpoint.method)
          {method, build_operation(endpoint, pricing_fn)}
        end)

      {path, methods}
    end)
  end

  # Builds an operation object for a single endpoint
  defp build_operation(endpoint, pricing_fn) do
    operation = %{
      "summary" => endpoint.description,
      "operationId" => Atom.to_string(endpoint.function),
      "responses" => build_responses(endpoint, pricing_fn)
    }

    operation = add_params_or_body(operation, endpoint)
    maybe_add_payment_info(operation, endpoint, pricing_fn)
  end

  # Adds query parameters (GET) or requestBody (POST)
  defp add_params_or_body(operation, %{method: :get, params: params}) when params != [] do
    parameters = Enum.map(params, &build_query_param/1)
    Map.put(operation, "parameters", parameters)
  end

  defp add_params_or_body(operation, %{method: :post, params: params}) when params != [] do
    Map.put(operation, "requestBody", build_request_body(params))
  end

  defp add_params_or_body(operation, _endpoint), do: operation

  # Builds a single query parameter
  defp build_query_param(param) do
    qp = %{
      "name" => param.name,
      "in" => "query",
      "required" => param[:required] == true,
      "schema" => type_to_schema(param[:type])
    }

    qp = maybe_put(qp, "description", param[:description])
    maybe_put(qp, "example", format_example(param[:example]))
  end

  # Builds the requestBody for POST endpoints
  defp build_request_body(params) do
    required =
      params
      |> Enum.filter(& &1[:required])
      |> Enum.map(& &1.name)

    properties =
      Map.new(params, fn param ->
        prop = type_to_schema(param[:type])
        prop = maybe_put(prop, "description", param[:description])
        prop = maybe_put(prop, "example", format_example(param[:example]))
        {param.name, prop}
      end)

    schema = %{"type" => "object", "properties" => properties}
    schema = if required == [], do: schema, else: Map.put(schema, "required", required)

    %{
      "required" => true,
      "content" => %{
        "application/json" => %{"schema" => schema}
      }
    }
  end

  # Builds response objects — always 200, optionally 402 for priced endpoints
  defp build_responses(endpoint, pricing_fn) do
    responses = %{
      "200" => %{
        "description" => "Successful response",
        "content" => %{"application/json" => %{"schema" => %{"type" => "object"}}}
      }
    }

    if has_pricing?(endpoint, pricing_fn) do
      Map.put(responses, "402", %{"description" => "Payment Required"})
    else
      responses
    end
  end

  # Adds x-payment-info extension when pricing applies
  defp maybe_add_payment_info(operation, endpoint, pricing_fn) do
    case get_pricing(endpoint, pricing_fn) do
      nil ->
        operation

      pricing ->
        Map.put(operation, "x-payment-info", %{
          "intent" => "charge",
          "method" => to_string(pricing.method),
          "amount" => to_string(pricing.amount),
          "currency" => to_string(pricing.currency)
        })
    end
  end

  # Adds servers array when URL is provided
  defp maybe_add_servers(doc, nil), do: doc
  defp maybe_add_servers(doc, url), do: Map.put(doc, "servers", [%{"url" => url}])

  # Adds x-service-info when categories or docs are provided
  defp maybe_add_service_info(doc, opts) do
    categories = Keyword.get(opts, :categories)
    docs = Keyword.get(opts, :docs)

    case {categories, docs} do
      {nil, nil} ->
        doc

      _ ->
        service_info = %{}
        service_info = maybe_put(service_info, "categories", categories)
        service_info = maybe_put_map(service_info, "docs", docs)
        Map.put(doc, "x-service-info", service_info)
    end
  end

  # Maps Elixir param types to JSON Schema
  defp type_to_schema(:string), do: %{"type" => "string"}
  defp type_to_schema(:integer), do: %{"type" => "integer"}
  defp type_to_schema(:float), do: %{"type" => "number"}
  defp type_to_schema(:boolean), do: %{"type" => "boolean"}
  defp type_to_schema(:array), do: %{"type" => "array", "items" => %{"type" => "string"}}
  # Unknown types default to string — safe fallback for forward compatibility
  defp type_to_schema(_), do: %{"type" => "string"}

  # Checks whether pricing applies to an endpoint
  defp has_pricing?(endpoint, pricing_fn), do: get_pricing(endpoint, pricing_fn) != nil

  defp get_pricing(_endpoint, nil), do: nil
  defp get_pricing(endpoint, pricing_fn), do: pricing_fn.(endpoint)

  # Puts a key only if value is non-nil
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Puts a map value with string keys — skips nil
  defp maybe_put_map(map, _key, nil), do: map

  defp maybe_put_map(map, key, value) when is_map(value) do
    stringified = Map.new(value, fn {k, v} -> {to_string(k), v} end)
    Map.put(map, key, stringified)
  end

  # Formats example values — skips lists and nil
  defp format_example(nil), do: nil
  defp format_example(val) when is_list(val), do: nil
  defp format_example(val), do: val
end
