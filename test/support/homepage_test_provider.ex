defmodule ApiToolkit.HomepageTestProvider do
  @moduledoc "Test provider with POST endpoints and :example params for Homepage tests."

  use ApiToolkit.Provider,
    name: "Homepage Test API",
    description: "Provider for homepage rendering tests",
    rate_limit: nil,
    cache_ttl_ms: 60_000

  defapi(:encode,
    path: "/api/encode",
    description: "Encode a value",
    params: [
      %{name: "value", type: :string, required: true, description: "Value to encode", example: "0xff"}
    ]
  )

  defapi(:batch,
    path: "/api/batch",
    method: :post,
    description: "Batch operation",
    params: [
      %{name: "items", type: :string, required: true, description: "Items to process"}
    ]
  )

  defapi(:status,
    path: "/api/status",
    description: "Service status",
    params: []
  )

  @doc false
  def encode(_params), do: {:ok, %{encoded: true}, 60_000}

  @doc false
  def batch(_params), do: {:ok, %{processed: 0}, 60_000}

  @doc false
  def status(_params), do: {:ok, %{status: :ok}, 60_000}

  defmodule Discovery do
    @moduledoc "Discovery module for HomepageTestProvider."
    use ApiToolkit.Discovery, providers: [ApiToolkit.HomepageTestProvider]
  end
end
