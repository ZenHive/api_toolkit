defmodule ApiToolkit.TestMCPPaymentHandler do
  @moduledoc """
  MCP handler generated from TestDiscovery with payment gating.

  TestProvider is `:paid`, OtherTestProvider is `:free` (default).
  Uses TestPaymentMethod for verification.
  """

  use ApiToolkit.MCP,
    discovery: ApiToolkit.TestDiscovery,
    server_info: %{name: "test-payment", version: "0.1.0"},
    strip_prefixes: ["test", "other"],
    tiers: %{ApiToolkit.TestProvider => :paid},
    payment: [
      secret_key: "test-secret-key-for-hmac-binding",
      realm: "test.example.com",
      method: ApiToolkit.TestPaymentMethod,
      amount: "1000",
      currency: "usd"
    ]
end

defmodule ApiToolkit.TestMCPPaymentCapsHandler do
  @moduledoc """
  Payment-gated MCP handler that also declares custom `:capabilities`.

  Exercises the deep merge of user-supplied capabilities with the generated
  payment capabilities in `capabilities/0`.
  """

  use ApiToolkit.MCP,
    discovery: ApiToolkit.TestDiscovery,
    server_info: %{name: "test-payment-caps", version: "0.1.0"},
    strip_prefixes: ["test", "other"],
    tiers: %{ApiToolkit.TestProvider => :paid},
    payment: [
      secret_key: "test-secret-key-for-hmac-binding",
      realm: "test.example.com",
      method: ApiToolkit.TestPaymentMethod,
      amount: "1000",
      currency: "usd",
      capabilities: %{logging: %{}, experimental: %{custom: %{enabled: true}}}
    ]
end
