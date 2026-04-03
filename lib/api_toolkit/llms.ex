defmodule ApiToolkit.LLMs do
  @moduledoc """
  Generates an LLM-readable Markdown document from Discovery metadata.

  Produces a `llms.txt`-style document optimized for AI agent consumption:
  Markdown headings, parameter tables with types and examples, and example
  request URLs. Auto-generated from `defapi` declarations.

  ## Usage

      # Minimal
      ApiToolkit.LLMs.render(MyDiscovery, name: "MyService", version: "1.0.0")

      # Full — with grouping, pricing, and discovery URLs
      ApiToolkit.LLMs.render(MyDiscovery,
        name: "MyService",
        version: "1.0.0",
        description: "Blockchain developer tools API.",
        url: "https://myservice.com",
        discovery_paths: [
          {"GET", "/api/discover", "JSON endpoint metadata"},
          {"GET", "/openapi.json", "OpenAPI 3.1 spec"},
          {"GET", "/llms.txt", "This document"}
        ],
        group_by: & &1[:tier],
        group_labels: %{free: "Free Endpoints", paid: "Paid Endpoints"},
        pricing: fn
          %{tier: :paid} -> "$0.01 per request via Tempo"
          _ -> nil
        end
      )

  ## Grouping

  By default, all endpoints render under a single "## Endpoints" heading.
  Pass `:group_by` with a function to split into multiple sections:

  - **By tier:** `group_by: & &1[:tier]`
  - **By provider:** `group_by: & &1.provider`
  - **By category:** `group_by: & List.first(&1[:categories] || [])`

  Use `:group_labels` to provide section headers for each group key.
  Keys without a label are stringified automatically.
  """

  @type discovery_module :: module()

  @type option ::
          {:name, String.t()}
          | {:version, String.t()}
          | {:description, String.t()}
          | {:url, String.t()}
          | {:discovery_paths, [{String.t(), String.t(), String.t()}]}
          | {:group_by, (map() -> term())}
          | {:group_labels, %{term() => String.t()}}
          | {:pricing, (map() -> String.t() | nil)}

  @doc """
  Renders the llms.txt document as a Markdown string.

  Requires a Discovery module and options with at least `:name` and `:version`.
  """
  @spec render(discovery_module(), [option()]) :: String.t()
  def render(discovery_module, opts) do
    name = Keyword.fetch!(opts, :name)
    version = Keyword.fetch!(opts, :version)
    description = Keyword.get(opts, :description)
    url = Keyword.get(opts, :url)
    discovery_paths = Keyword.get(opts, :discovery_paths)
    group_by = Keyword.get(opts, :group_by)
    group_labels = Keyword.get(opts, :group_labels, %{})
    pricing_fn = Keyword.get(opts, :pricing)

    endpoints = discovery_module.all_endpoints()

    [
      header(name, version, description, url),
      endpoint_sections(endpoints, group_by, group_labels, pricing_fn),
      discovery_section(discovery_paths)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # Builds the Markdown header: title, description, and optional base URL
  defp header(name, version, description, url) do
    lines = ["# #{name} API v#{version}"]
    lines = if description, do: lines ++ ["", description], else: lines
    lines = if url, do: lines ++ ["", "Base URL: #{url}"], else: lines
    Enum.join(lines, "\n")
  end

  # Renders endpoint sections — flat or grouped
  defp endpoint_sections(endpoints, nil, _labels, pricing_fn) do
    section("Endpoints", endpoints, pricing_fn)
  end

  defp endpoint_sections(endpoints, group_by, labels, pricing_fn) do
    endpoints
    |> Enum.group_by(group_by)
    |> Enum.sort_by(fn {key, _} -> inspect(key) end)
    |> Enum.map(fn {key, group} ->
      title = Map.get(labels, key, stringify_key(key))
      section(title, group, pricing_fn)
    end)
  end

  defp section(_title, [], _pricing_fn), do: nil

  defp section(title, endpoints, pricing_fn) do
    blocks = Enum.map_join(endpoints, "\n", &format_endpoint(&1, pricing_fn))
    "\n## #{title}\n\n#{blocks}"
  end

  # Formats a single endpoint as a Markdown block with params
  defp format_endpoint(endpoint, pricing_fn) do
    method = endpoint.method |> Atom.to_string() |> String.upcase()
    heading = "### #{method} #{endpoint.path}"
    heading = if endpoint[:description], do: "#{heading} — #{endpoint.description}", else: heading

    parts = [heading]
    parts = parts ++ param_block(endpoint.params)
    parts = parts ++ example_line(endpoint)
    parts = parts ++ pricing_line(endpoint, pricing_fn)

    Enum.join(parts, "\n")
  end

  # Renders the parameter list as Markdown bullet points
  defp param_block([]), do: []

  defp param_block(params) do
    lines = Enum.map(params, &format_param/1)
    ["", "Parameters:" | lines]
  end

  defp format_param(param) do
    type = param[:type] || :string
    required = if param[:required], do: "required", else: "optional"
    desc = param[:description]
    example = param[:example]

    base = "- `#{param.name}` (#{type}, #{required})"
    base = if desc, do: "#{base} — #{desc}", else: base
    base = if example && !is_list(example), do: "#{base}. Example: #{inspect(example)}", else: base
    base
  end

  # Builds an example request line for GET endpoints
  defp example_line(%{method: :get, path: path, params: params}) do
    pairs =
      params
      |> Enum.filter(&match?(%{example: val} when val != nil and not is_list(val), &1))
      |> Enum.map(fn p -> "#{p.name}=#{URI.encode_www_form(to_string(p.example))}" end)

    case pairs do
      [] -> []
      pairs -> ["", "Example: `GET #{path}?#{Enum.join(pairs, "&")}`"]
    end
  end

  defp example_line(_post), do: []

  # Renders optional pricing line via user-provided function
  defp pricing_line(_endpoint, nil), do: []

  defp pricing_line(endpoint, pricing_fn) do
    case pricing_fn.(endpoint) do
      nil -> []
      text -> ["", "Pricing: #{text}"]
    end
  end

  # Renders the discovery paths section
  defp discovery_section(nil), do: nil
  defp discovery_section([]), do: nil

  defp discovery_section(paths) do
    lines = Enum.map_join(paths, "\n", fn {method, path, desc} -> "- #{method} #{path} — #{desc}" end)
    "\n---\n\n## Discovery\n\n#{lines}"
  end

  # Converts any term to a string safe for section headers
  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: inspect(key)
end
