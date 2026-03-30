defmodule ApiToolkit.OtherTestProvider do
  @moduledoc "Second test provider for discovery tests."

  use ApiToolkit.Provider,
    name: "Other API",
    description: "Another test provider",
    rate_limit: nil,
    cache_ttl_ms: 60_000

  defapi(:list,
    path: "/other/list",
    description: "List items",
    params: [],
    categories: [:data]
  )

  @doc false
  def list(_params), do: {:ok, [], 60_000}
end
