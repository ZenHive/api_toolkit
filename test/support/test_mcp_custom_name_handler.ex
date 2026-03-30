defmodule ApiToolkit.TestMCPCustomNameHandler do
  @moduledoc "MCP handler with custom :tool_name function via `use ApiToolkit.MCP`."

  use ApiToolkit.MCP,
    discovery: ApiToolkit.TestDiscovery,
    server_info: %{name: "custom-names", version: "0.1.0"},
    tool_name: fn ep -> "custom_#{ep.function}" end
end
