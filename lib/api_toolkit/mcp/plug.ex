defmodule ApiToolkit.MCP.Plug do
  @moduledoc """
  HTTP transport for the MCP JSON-RPC server.

  Thin `Plug` layer that reads the request body, delegates to
  `ApiToolkit.MCP.Handler`, and sends the JSON response. POST-only —
  all other methods receive 405.

  ## Usage

  Place `Plug.Parsers` with JSON support before this plug, then forward:

      defmodule MyApp.Router do
        use Plug.Router

        plug Plug.Parsers, parsers: [:json], json_decoder: JSON
        plug :match
        plug :dispatch

        forward "/mcp", to: ApiToolkit.MCP.Plug, init_opts: [handler: MyApp.MCPHandler]
      end

  ## Options

  - `:handler` (required) — module implementing `ApiToolkit.MCP.Server`
  - `:assigns` (optional) — static map passed to arity-2 tool callbacks (default: `%{}`)

  ## Parse Error Handling

  When `Plug.Parsers` is in the pipeline, JSON parse errors are raised by the
  parser (`Plug.Parsers.ParseError`) before reaching this plug. The built-in
  `-32700` parse error response only applies when `Plug.Parsers` is not used.
  To customize parse error responses, use `Plug.ErrorHandler` in your router.
  """

  @behaviour Plug

  import Plug.Conn

  alias ApiToolkit.MCP.Handler

  @impl true
  @spec init(keyword()) :: map()
  def init(opts) do
    %{handler: Keyword.fetch!(opts, :handler), assigns: Keyword.get(opts, :assigns, %{})}
  end

  @impl true
  @spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def call(%{method: "POST"} = conn, %{handler: handler, assigns: assigns}) do
    assigns = put_payment_config(handler, assigns)

    case_result =
      case decode_body(conn) do
        {:ok, message} ->
          message
          |> dispatch(handler, assigns)
          |> send_handler_response(conn)

        {:error, reason} ->
          json_resp(conn, 400, %{
            jsonrpc: "2.0",
            id: nil,
            error: %{code: -32_700, message: reason}
          })
      end

    halt(case_result)
  end

  def call(conn, _opts) do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(405, "Method Not Allowed")
    |> halt()
  end

  # Auto-detects payment_config/0 on the handler and injects it into assigns, so
  # `use ApiToolkit.MCP, payment: [...]` works without manual assigns wiring.
  # Explicit :mpp_payment in assigns takes precedence.
  #
  # Resolved per request rather than in init/1: Phoenix routers evaluate init/1 at
  # COMPILE time (`plug_init_mode: :compile`, the prod default), which would bake
  # the build machine's %Payment.Config{} — secret key included — into the router's
  # BEAM, and would silently skip gating whenever the handler module isn't compiled
  # yet when the router compiles.
  @spec put_payment_config(module(), map()) :: map()
  defp put_payment_config(handler, assigns) do
    if not Map.has_key?(assigns, :mpp_payment) and Code.ensure_loaded?(handler) and
         function_exported?(handler, :payment_config, 0) do
      Map.put(assigns, :mpp_payment, handler.payment_config())
    else
      assigns
    end
  end

  # Routes single messages vs batch arrays to the appropriate Handler function
  defp dispatch(messages, handler, assigns) when is_list(messages), do: Handler.handle_batch(messages, handler, assigns)

  defp dispatch(message, handler, assigns) when is_map(message), do: Handler.handle(message, handler, assigns)

  defp dispatch(_other, _handler, _assigns),
    do: {:error, 400, %{jsonrpc: "2.0", id: nil, error: %{code: -32_600, message: "Invalid request"}}}

  # Translates Handler response tuples to Plug responses
  defp send_handler_response({:reply, 200, body}, conn), do: json_resp(conn, 200, body)
  defp send_handler_response({:reply, 202, nil}, conn), do: send_resp(conn, 202, "")
  defp send_handler_response({:error, 400, body}, conn), do: json_resp(conn, 400, body)

  # Reads body from already-parsed body_params or raw body.
  # Plug.Parsers wraps top-level JSON arrays as %{"_json" => [...]}, so unwrap them
  # to let dispatch/3 route batches correctly.
  # Plug.Conn.body_params is always %Plug.Conn.Unfetched{} (no parser) or a map (parsed).
  # Empty maps (%{}) come from valid JSON "{}" — must route to dispatch, not raw body read.
  defp decode_body(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} -> read_raw_body(conn)
      %{"_json" => list} when is_list(list) -> {:ok, list}
      %{} = params -> {:ok, params}
    end
  end

  defp read_raw_body(conn) do
    case read_body(conn) do
      {:ok, body, _conn} ->
        case JSON.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, "Parse error: invalid JSON"}
        end

      {:more, _data, _conn} ->
        {:error, "Parse error: request body too large"}

      {:error, _reason} ->
        {:error, "Parse error: could not read body"}
    end
  end

  defp json_resp(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
