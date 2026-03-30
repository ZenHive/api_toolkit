defmodule ApiToolkit.MCP.Handler do
  @moduledoc """
  Pure-function JSON-RPC 2.0 dispatch for MCP protocol messages.

  Takes a decoded JSON-RPC request map and a handler module (implementing
  `ApiToolkit.MCP.Server`), returns a response tuple. No Plug dependency —
  fully unit-testable and transport-agnostic.

  ## Usage

      case ApiToolkit.MCP.Handler.handle(decoded_message, MyApp.MCPHandler) do
        {:reply, 200, body} -> send_json(conn, 200, body)
        {:reply, 202, nil}  -> send_resp(conn, 202, "")
        {:error, status, body} -> send_json(conn, status, body)
      end

  ## Protocol

  Implements MCP protocol version `2025-03-26` over JSON-RPC 2.0.
  """

  @protocol_version "2025-03-26"

  @typedoc "Handler response: reply with HTTP status and optional body, or error."
  @type response ::
          {:reply, 200, map() | [map()]}
          | {:reply, 202, nil}
          | {:error, 400, map()}

  @doc """
  Dispatches a decoded JSON-RPC 2.0 message to the appropriate handler.

  Returns `{:reply, status, body}` for successful handling or
  `{:error, status, body}` for protocol errors.
  """
  @spec handle(map(), module()) :: response()
  @spec handle(map(), module(), map()) :: response()
  def handle(message, handler, assigns \\ %{}) do
    case validate_jsonrpc(message) do
      {:ok, :request, message} -> handle_request(message, handler, assigns)
      {:ok, :notification, message} -> handle_notification(message)
      {:error, reason} -> {:error, 400, jsonrpc_error(nil, -32_600, reason)}
    end
  end

  @doc """
  Dispatches a JSON-RPC 2.0 batch (array of messages).

  Per the JSON-RPC 2.0 spec: processes each element independently, collects
  responses (notifications produce no response), and returns the array.
  Empty arrays are invalid. If all messages are notifications, returns 202.
  """
  @spec handle_batch([map()], module(), map()) :: response()
  def handle_batch([], _handler, _assigns) do
    {:error, 400, jsonrpc_error(nil, -32_600, "Invalid request: empty batch")}
  end

  def handle_batch(messages, handler, assigns) when is_list(messages) do
    # MCP 2025-03-26 lifecycle: initialize must be a standalone request, not part of a batch
    if Enum.any?(messages, &batch_contains_initialize?/1) do
      {:error, 400, jsonrpc_error(nil, -32_600, "Invalid request: initialize must not be part of a batch")}
    else
      handle_batch_messages(messages, handler, assigns)
    end
  end

  defp batch_contains_initialize?(%{"method" => "initialize"}), do: true
  defp batch_contains_initialize?(_), do: false

  defp handle_batch_messages(messages, handler, assigns) do
    responses =
      messages
      |> Enum.map(&handle(&1, handler, assigns))
      |> Enum.reject(fn {_, status, _} -> status == 202 end)
      |> Enum.map(fn
        {:reply, _status, body} -> body
        {:error, _status, body} -> body
      end)

    case responses do
      [] -> {:reply, 202, nil}
      responses -> {:reply, 200, responses}
    end
  end

  # JSON-RPC 2.0 validation

  defp validate_jsonrpc(%{"jsonrpc" => "2.0", "method" => method} = message) when is_binary(method) do
    if Map.has_key?(message, "id") do
      case message["id"] do
        id when is_binary(id) or is_number(id) -> {:ok, :request, message}
        _ -> {:error, "Invalid request ID"}
      end
    else
      {:ok, :notification, message}
    end
  end

  defp validate_jsonrpc(%{"jsonrpc" => "2.0"}), do: {:error, "Missing method field"}
  defp validate_jsonrpc(_), do: {:error, "Invalid JSON-RPC 2.0 message"}

  # Request dispatch — split into function clauses to keep cyclomatic complexity low

  # JSON-RPC 2.0: params MUST be a structured value (object or array).
  # Non-map values are coerced to %{} — downstream validation catches missing fields.
  defp handle_request(%{"method" => method, "id" => id} = message, handler, assigns) do
    params =
      case Map.get(message, "params", %{}) do
        p when is_map(p) -> p
        _ -> %{}
      end

    dispatch_method(method, id, params, handler, assigns)
  end

  defp dispatch_method("initialize", id, params, handler, _assigns), do: handle_initialize(id, params, handler)
  defp dispatch_method("ping", id, _params, _handler, _assigns), do: {:reply, 200, wrap_result(id, %{})}
  defp dispatch_method("tools/list", id, _params, handler, _assigns), do: handle_tools_list(id, handler)
  defp dispatch_method("tools/call", id, params, handler, assigns), do: handle_tools_call(id, params, handler, assigns)
  defp dispatch_method("resources/list", id, _params, handler, _assigns), do: handle_resources_list(id, handler)
  defp dispatch_method("resources/read", id, params, handler, _assigns), do: handle_resources_read(id, params, handler)
  defp dispatch_method("prompts/list", id, _params, handler, _assigns), do: handle_prompts_list(id, handler)
  defp dispatch_method("prompts/get", id, params, handler, _assigns), do: handle_prompts_get(id, params, handler)

  defp dispatch_method(method, id, _params, _handler, _assigns),
    do: {:reply, 200, jsonrpc_error(id, -32_601, "Method not found", %{method: method})}

  # Notification dispatch

  defp handle_notification(%{"method" => "notifications/initialized"}), do: {:reply, 202, nil}
  defp handle_notification(%{"method" => "notifications/cancelled"}), do: {:reply, 202, nil}
  defp handle_notification(%{"method" => _method}), do: {:reply, 202, nil}

  # initialize — version negotiation + capabilities

  # MCP lifecycle spec: server MUST always respond with its supported protocolVersion.
  # The client decides whether to disconnect if it can't work with the server's version.
  defp handle_initialize(id, params, handler) do
    case params["protocolVersion"] do
      nil ->
        {:reply, 200, jsonrpc_error(id, -32_602, "Missing required parameter: protocolVersion")}

      _version ->
        info = handler.server_info()
        tools = strip_callbacks(handler.tools())

        capabilities =
          %{tools: %{listChanged: false}}
          |> maybe_merge_resource_capabilities(handler)
          |> maybe_merge_prompt_capabilities(handler)
          |> maybe_merge_custom_capabilities(handler)

        result = %{
          protocolVersion: @protocol_version,
          capabilities: capabilities,
          serverInfo: info,
          tools: tools
        }

        {:reply, 200, wrap_result(id, result)}
    end
  end

  # Advertise resource capability only when handler can both list AND read resources.
  # resources/0 without read_resource/1 would claim support it can't fulfill.
  defp maybe_merge_resource_capabilities(caps, handler) do
    if exports?(handler, :resources, 0) and exports?(handler, :read_resource, 1),
      do: Map.put(caps, :resources, %{listChanged: false}),
      else: caps
  end

  # Advertise prompt capability only when handler can both list AND resolve prompts.
  defp maybe_merge_prompt_capabilities(caps, handler) do
    if exports?(handler, :prompts, 0) and exports?(handler, :get_prompt, 2),
      do: Map.put(caps, :prompts, %{listChanged: false}),
      else: caps
  end

  defp maybe_merge_custom_capabilities(caps, handler) do
    if exports?(handler, :capabilities, 0),
      do: Map.merge(caps, handler.capabilities()),
      else: caps
  end

  # tools/list

  defp handle_tools_list(id, handler) do
    tools = strip_callbacks(handler.tools())
    {:reply, 200, wrap_result(id, %{tools: tools})}
  end

  # tools/call — safe dispatch with exception catching

  defp handle_tools_call(id, %{"name" => name} = params, handler, assigns) do
    args = Map.get(params, "arguments", %{})

    case find_tool(handler, name) do
      {:ok, tool} ->
        result = safe_call_tool(tool, args, assigns)
        {:reply, 200, wrap_result(id, format_tool_result(result))}

      :error ->
        {:reply, 200, jsonrpc_error(id, -32_602, "Tool not found", %{name: name})}
    end
  end

  defp handle_tools_call(id, _params, _handler, _assigns) do
    {:reply, 200, jsonrpc_error(id, -32_602, "Missing required parameter: name")}
  end

  defp find_tool(handler, name) do
    case Enum.find(handler.tools(), fn tool -> tool.name == name end) do
      nil -> :error
      tool -> {:ok, tool}
    end
  end

  defp safe_call_tool(tool, args, assigns) do
    call_tool(tool.callback, args, assigns)
  catch
    kind, reason ->
      message = Exception.format(kind, reason, __STACKTRACE__)
      {:error, "Failed to call tool: #{message}"}
  end

  defp call_tool(callback, args, assigns) when is_function(callback, 2), do: callback.(args, assigns)
  defp call_tool(callback, args, _assigns) when is_function(callback, 1), do: callback.(args)

  # Tool result formatting

  defp format_tool_result({:ok, text}) when is_binary(text) do
    %{content: [%{type: "text", text: text}]}
  end

  defp format_tool_result({:ok, data}) when is_map(data) do
    data
  end

  defp format_tool_result({:ok, text, metadata}) when is_binary(text) and is_map(metadata) do
    %{content: [%{type: "text", text: text}], _meta: metadata}
  end

  defp format_tool_result({:error, :invalid_arguments}) do
    %{content: [%{type: "text", text: "Invalid arguments"}], isError: true}
  end

  defp format_tool_result({:error, message}) when is_binary(message) do
    %{content: [%{type: "text", text: message}], isError: true}
  end

  defp format_tool_result(other) do
    %{content: [%{type: "text", text: "Unexpected tool result: #{inspect(other)}"}], isError: true}
  end

  # resources/list

  defp handle_resources_list(id, handler) do
    resources =
      if exports?(handler, :resources, 0),
        do: handler.resources(),
        else: []

    {:reply, 200, wrap_result(id, %{resources: resources})}
  end

  # resources/read

  defp handle_resources_read(id, %{"uri" => uri}, handler) do
    if exports?(handler, :read_resource, 1) do
      case handler.read_resource(uri) do
        {:ok, content} ->
          {:reply, 200, wrap_result(id, %{contents: [%{uri: uri, text: content}]})}

        {:error, reason} ->
          {:reply, 200, jsonrpc_error(id, -32_602, reason)}
      end
    else
      {:reply, 200, jsonrpc_error(id, -32_601, "Resources not supported")}
    end
  end

  defp handle_resources_read(id, _params, _handler) do
    {:reply, 200, jsonrpc_error(id, -32_602, "Missing required parameter: uri")}
  end

  # prompts/list

  defp handle_prompts_list(id, handler) do
    prompts =
      if exports?(handler, :prompts, 0),
        do: handler.prompts(),
        else: []

    {:reply, 200, wrap_result(id, %{prompts: prompts})}
  end

  # prompts/get

  defp handle_prompts_get(id, %{"name" => name} = params, handler) do
    if exports?(handler, :get_prompt, 2) do
      args = Map.get(params, "arguments", %{})

      case handler.get_prompt(name, args) do
        {:ok, text} ->
          {:reply, 200, wrap_result(id, %{messages: [%{role: "user", content: %{type: "text", text: text}}]})}

        {:error, reason} ->
          {:reply, 200, jsonrpc_error(id, -32_602, reason)}
      end
    else
      {:reply, 200, jsonrpc_error(id, -32_601, "Prompts not supported")}
    end
  end

  defp handle_prompts_get(id, _params, _handler) do
    {:reply, 200, jsonrpc_error(id, -32_602, "Missing required parameter: name")}
  end

  # JSON-RPC response helpers

  defp wrap_result(id, result), do: %{jsonrpc: "2.0", id: id, result: result}

  defp jsonrpc_error(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end

  defp jsonrpc_error(id, code, message, data) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message, data: data}}
  end

  # function_exported?/3 doesn't auto-load modules. This ensures the module
  # is loaded before checking, so capability checks work regardless of call order.
  defp exports?(module, function, arity) do
    Code.ensure_loaded(module)
    function_exported?(module, function, arity)
  end

  # Strips callback functions from tool definitions before serialization
  defp strip_callbacks(tools) do
    Enum.map(tools, fn tool ->
      tool
      |> Map.put(:description, String.trim(tool.description))
      |> Map.delete(:callback)
    end)
  end
end
