defmodule ApiToolkit.Homepage do
  @moduledoc """
  Generates a plain-text homepage from Discovery metadata.

  Auto-generated from `defapi` declarations — stays in sync automatically.
  Designed to be scannable in a terminal while giving agents and humans
  the full endpoint map.

  ## Usage

      # Minimal — flat endpoint list
      ApiToolkit.Homepage.render(MyDiscovery, name: "MyService", version: "1.0.0")

      # Full — with grouping, discovery URLs, and footer
      ApiToolkit.Homepage.render(MyDiscovery,
        name: "MyService",
        version: "1.0.0",
        description: "Blockchain developer tools API.",
        url: "https://myservice.com",
        discovery_paths: [
          {"GET", "/api/discover", "JSON endpoint metadata"},
          {"GET", "/openapi.json", "OpenAPI 3.1 spec"},
          {"GET", "/llms.txt", "LLM-readable docs"}
        ],
        group_by: & &1[:tier],
        group_labels: %{free: "Free endpoints:", paid: "Paid endpoints (402 Payment Required):"}
      )

  ## Grouping

  By default, all endpoints render in a single flat list under "Endpoints:".
  Pass `:group_by` with a function to split endpoints into sections:

  - **By tier:** `group_by: & &1[:tier]`
  - **By provider:** `group_by: & &1.provider`
  - **By category:** `group_by: & List.first(&1[:categories] || [])`

  Use `:group_labels` to provide human-readable section headers for each
  group key. Keys without a label are stringified automatically.
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

  @doc """
  Renders the homepage as a plain-text string.

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

    endpoints = discovery_module.all_endpoints()

    [
      header(name, version, description),
      endpoint_sections(endpoints, group_by, group_labels),
      discovery_section(discovery_paths),
      footer(url)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # Builds the header block: name, version, and optional description
  defp header(name, version, nil), do: "#{name} v#{version}"
  defp header(name, version, description), do: "#{name} v#{version}\n\n#{description}"

  # Renders endpoint sections — flat list or grouped
  defp endpoint_sections(endpoints, nil, _labels) do
    section("Endpoints:", endpoints)
  end

  defp endpoint_sections(endpoints, group_by, labels) do
    endpoints
    |> Enum.group_by(group_by)
    |> Enum.sort_by(fn {key, _} -> inspect(key) end)
    |> Enum.map(fn {key, group} ->
      title = Map.get(labels, key, "#{stringify_key(key)}:")
      section(title, group)
    end)
  end

  defp section(_title, []), do: nil

  defp section(title, endpoints) do
    lines = Enum.map_join(endpoints, "\n", &format_endpoint/1)
    "\n#{title}\n#{lines}"
  end

  defp format_endpoint(endpoint) do
    method = endpoint.method |> Atom.to_string() |> String.upcase()
    query = example_query(endpoint)
    "  #{method} #{endpoint.path}#{query}"
  end

  # Builds example query string from GET params that have :example values
  defp example_query(%{method: :get, params: params}) do
    pairs =
      params
      |> Enum.filter(&match?(%{example: val} when val != nil and not is_list(val), &1))
      |> Enum.map(fn p -> "#{p.name}=#{URI.encode_www_form(to_string(p.example))}" end)

    case pairs do
      [] -> ""
      pairs -> "?" <> Enum.join(pairs, "&")
    end
  end

  defp example_query(_post), do: ""

  # Renders the discovery paths section
  defp discovery_section(nil), do: nil

  defp discovery_section(paths) do
    lines = Enum.map_join(paths, "\n", fn {method, path, desc} -> "  #{method} #{path}  #{desc}" end)
    "\nDiscovery:\n#{lines}"
  end

  # Converts any term to a string safe for section headers
  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: inspect(key)

  # Renders the footer URL
  defp footer(nil), do: nil
  defp footer(url), do: "\n#{url}\n"
end
