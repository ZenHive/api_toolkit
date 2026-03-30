defmodule ApiToolkit.TestMCPHandlerFull do
  @moduledoc """
  Test handler implementing all optional `ApiToolkit.MCP.Server` callbacks.

  Used to test success paths for resources/read and prompts/get, and to verify
  capability advertisement when both listing AND operation callbacks exist.
  """

  @behaviour ApiToolkit.MCP.Server

  @impl true
  def server_info, do: %{name: "full-handler", version: "0.1.0"}

  @impl true
  def tools, do: []

  # Resources

  @impl true
  def resources do
    [
      %{uri: "api:///openapi.json", name: "openapi", description: "OpenAPI 3.1 spec", mimeType: "application/json"},
      %{uri: "api:///readme", name: "readme", description: "Project README", mimeType: "text/plain"}
    ]
  end

  @impl true
  def read_resource("api:///openapi.json"), do: {:ok, ~s({"openapi":"3.1.0"})}
  def read_resource("api:///readme"), do: {:ok, "# ApiToolkit\n\nReusable API infrastructure."}
  def read_resource(_uri), do: {:error, "Resource not found"}

  # Prompts

  @impl true
  def prompts do
    [
      %{
        name: "search_help",
        description: "How to search the API",
        arguments: [%{name: "topic", description: "Topic to search for", required: true}]
      },
      %{
        name: "greeting",
        description: "A simple greeting",
        arguments: []
      }
    ]
  end

  @impl true
  def get_prompt("search_help", %{"topic" => topic}) do
    {:ok, "Search for #{topic} using the search endpoint with ?q=#{topic}"}
  end

  def get_prompt("search_help", _args), do: {:error, "Missing required argument: topic"}
  def get_prompt("greeting", _args), do: {:ok, "Hello! How can I help you today?"}
  def get_prompt(_name, _args), do: {:error, "Prompt not found"}
end
