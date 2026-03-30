defmodule ApiToolkit.TestDiscovery do
  @moduledoc "Test discovery module for unit tests."

  use ApiToolkit.Discovery,
    providers: [
      ApiToolkit.TestProvider,
      ApiToolkit.OtherTestProvider
    ]
end
