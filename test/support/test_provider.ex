defmodule ApiToolkit.TestProvider do
  @moduledoc "Test provider for unit tests."

  use ApiToolkit.Provider,
    name: "Test API",
    description: "A test provider",
    rate_limit: "1 req/sec",
    cache_ttl_ms: 300_000

  defapi(:search,
    path: "/test/search",
    description: "Search endpoint",
    params: [
      %{name: "q", type: :string, required: true, description: "Search query"}
    ],
    categories: [:web]
  )

  defapi(:detail,
    path: "/test/detail/:id",
    description: "Detail endpoint",
    params: [
      %{name: "id", type: :string, required: true, description: "Item ID"}
    ]
  )

  @doc false
  def search(%{"q" => q}) when byte_size(q) > 0, do: {:ok, %{results: []}, 300_000}
  def search(_params), do: {:error, :invalid_params}

  @doc false
  def detail(%{"id" => id}) when byte_size(id) > 0, do: {:ok, %{id: id}, 300_000}
  def detail(_params), do: {:error, :invalid_params}
end
