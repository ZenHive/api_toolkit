defmodule ApiToolkit.TestMCPResourcesPromptsHandler do
  @moduledoc """
  MCP handler generated from TestDiscovery with `:resources` and `:prompts` options.
  Tests the `use ApiToolkit.MCP` macro's resource/prompt registration.
  """

  use ApiToolkit.MCP,
    discovery: ApiToolkit.TestDiscovery,
    server_info: %{name: "test-resources-prompts", version: "0.1.0"},
    strip_prefixes: ["test", "other"],
    resources: [
      %{
        uri: "api:///spec.json",
        name: "spec",
        description: "API specification",
        mimeType: "application/json",
        read: fn -> ~s({"version":"1.0"}) end
      },
      %{
        uri: "api:///help.txt",
        name: "help",
        description: "Help text",
        mimeType: "text/plain",
        read: fn -> "Use the search tool to find results." end
      }
    ],
    prompts: [
      %{
        name: "search_guide",
        description: "How to search",
        arguments: [%{name: "topic", required: true, description: "Search topic"}],
        handler: fn
          %{"topic" => topic} -> {:ok, "Search for #{topic} using ?q=#{topic}"}
          _args -> {:error, "Missing required argument: topic"}
        end
      },
      %{
        name: "welcome",
        description: "Welcome message",
        arguments: [],
        handler: fn _args -> {:ok, "Welcome to the API!"} end
      }
    ]
end
