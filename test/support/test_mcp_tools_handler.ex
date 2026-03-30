defmodule ApiToolkit.TestMCPToolsHandler do
  @moduledoc "MCP handler generated from TestDiscovery via `use ApiToolkit.MCP`."

  use ApiToolkit.MCP,
    discovery: ApiToolkit.TestDiscovery,
    server_info: %{name: "test-tools", version: "0.1.0"},
    strip_prefixes: ["test", "other"]
end
