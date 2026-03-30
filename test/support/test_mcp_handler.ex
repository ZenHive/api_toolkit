defmodule ApiToolkit.TestMCPHandler do
  @moduledoc """
  Test handler implementing `ApiToolkit.MCP.Server` for MCP protocol tests.

  Provides four tools: echo (stateless), greet (with assigns), crash (raises),
  and bad_return (unexpected return value).
  """

  @behaviour ApiToolkit.MCP.Server

  @impl true
  def server_info, do: %{name: "test-mcp-server", version: "0.1.0"}

  @impl true
  def tools do
    [
      %{
        name: "echo",
        description: "Echoes back the input text",
        inputSchema: %{
          type: "object",
          properties: %{text: %{type: "string", description: "Text to echo"}},
          required: ["text"]
        },
        callback: &echo/1
      },
      %{
        name: "greet",
        description: "Greets using context from assigns",
        inputSchema: %{
          type: "object",
          properties: %{name: %{type: "string", description: "Name to greet"}},
          required: ["name"]
        },
        callback: &greet/2
      },
      %{
        name: "crash",
        description: "Always raises an exception (for testing error handling)",
        inputSchema: %{type: "object", properties: %{}},
        callback: &crash/1
      },
      %{
        name: "bad_return",
        description: "Returns an unexpected value (for testing catch-all formatting)",
        inputSchema: %{type: "object", properties: %{}},
        callback: &bad_return/1
      },
      %{
        name: "structured",
        description: "Returns a pre-formatted MCP result map (for testing {:ok, map} path)",
        inputSchema: %{type: "object", properties: %{}},
        callback: &structured/1
      },
      %{
        name: "with_meta",
        description: "Returns text with metadata (for testing {:ok, text, metadata} path)",
        inputSchema: %{type: "object", properties: %{text: %{type: "string"}}},
        callback: &with_meta/1
      }
    ]
  end

  defp echo(%{"text" => text}), do: {:ok, text}
  defp echo(_), do: {:error, :invalid_arguments}

  defp greet(%{"name" => name}, assigns) do
    prefix = Map.get(assigns, :greeting_prefix, "Hello")
    {:ok, "#{prefix}, #{name}!"}
  end

  defp greet(_, _), do: {:error, :invalid_arguments}

  defp crash(_), do: raise("intentional crash for testing")

  defp bad_return(_), do: {:error, :not_found}

  defp structured(_), do: {:ok, %{content: [%{type: "text", text: "structured"}]}}

  defp with_meta(%{"text" => text}), do: {:ok, text, %{request_id: "abc-123"}}
  defp with_meta(_), do: {:ok, "default", %{request_id: "none"}}
end

defmodule ApiToolkit.TestMCPHandlerResourcesOnly do
  @moduledoc """
  Handler that implements resources/0 but NOT read_resource/1.
  Used to verify capability advertisement requires both callbacks.
  """

  @behaviour ApiToolkit.MCP.Server

  @impl true
  def server_info, do: %{name: "resources-only", version: "0.1.0"}

  @impl true
  def tools, do: []

  @impl true
  def resources, do: [%{uri: "test://doc", name: "doc", description: nil, mimeType: "text/plain"}]
end

defmodule ApiToolkit.TestMCPHandlerPromptsOnly do
  @moduledoc """
  Handler that implements prompts/0 but NOT get_prompt/2.
  Used to verify capability advertisement requires both callbacks.
  """

  @behaviour ApiToolkit.MCP.Server

  @impl true
  def server_info, do: %{name: "prompts-only", version: "0.1.0"}

  @impl true
  def tools, do: []

  @impl true
  def prompts, do: [%{name: "greet", description: "Greeting", arguments: []}]
end
