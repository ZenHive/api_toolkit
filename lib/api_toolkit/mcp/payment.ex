defmodule ApiToolkit.MCP.Payment do
  @moduledoc """
  Per-tool payment gating for MCP JSON-RPC transport.

  The MPP protocol work — challenge generation, HMAC binding, JCS
  canonicalization, credential verification, replay protection, receipt
  attachment, and JSON-RPC error shaping — is owned by `MPP.Mcp`, the
  provider's own MCP transport. This module supplies only what MPP has no
  concept of:

    * **tier gating** — which tools are paid at all (`requires_payment?/2`)
    * **capability advertisement** for the MCP `initialize` response
    * **rejection recording** via `ApiToolkit.Rejections`

  ## Architecture

  Gating lives in `ApiToolkit.MCP.Handler`, not in Plug, because credentials
  travel inside JSON-RPC messages (`params._meta` or root `_meta`), not HTTP
  headers. Handler resolves the tool, then hands a thunk to `gate_tool_call/5`;
  MPP invokes that thunk only after a credential verifies.

  ## Error codes

    * `-32042` — Payment Required (challenges in `error.data.challenges`)
    * `-32602` — malformed credential
    * `-32043` — verification failed (bad proof, expired, replayed, mismatched)

  Every error carries RFC 9457 problem details in `error.data.problem`.

  ## Paid tools that fail

  MPP claims the credential *before* invoking the tool, so a paid tool that
  raises or returns `{:error, _}` still consumes the payment and still receives
  a receipt alongside `isError: true`. That is deliberate: the funds were
  captured during verification, and withholding the receipt would leave the
  caller without proof of payment. Validate arguments cheaply before doing
  billable work.

  ## Usage

  Typically used via `use ApiToolkit.MCP` with the `:payment` option, which
  generates `capabilities/0` and `payment_config/0`. Can also be used directly
  from a hand-written `ApiToolkit.MCP.Server` implementation.
  """

  defmodule Config do
    @moduledoc """
    Payment configuration: an `MPP.Plug.Config` plus api_toolkit extras.

    Built by `ApiToolkit.MCP.Payment.init/1` and stored in Handler assigns
    under `:mpp_payment`.
    """

    @type t :: %__MODULE__{mpp: MPP.Plug.Config.t(), rejections: atom() | nil}

    @enforce_keys [:mpp]
    defstruct [:mpp, :rejections]
  end

  @doc """
  Builds payment configuration from keyword options.

  All options are forwarded to `MPP.Mcp.init/1` (which delegates to
  `MPP.Plug.init/1`) except the two api_toolkit-specific ones:

    * `:rejections` — name of an `ApiToolkit.Rejections` tracker, or `nil`
    * `:capabilities` — consumed at compile time by `use ApiToolkit.MCP`

  See `MPP.Plug.init/1` for the full option set: `:secret_key` and `:realm`
  are required, `:method` or `:methods` declares pricing, and `:expires_in`,
  `:opaque`, `:digest`, `:intent`, and `:store` are optional.

  ## Examples

      iex> config = ApiToolkit.MCP.Payment.init(
      ...>   secret_key: "s3cret",
      ...>   realm: "api.example.com",
      ...>   method: ApiToolkit.TestPaymentMethod,
      ...>   amount: "1000",
      ...>   currency: "usd"
      ...> )
      iex> config.mpp.realm
      "api.example.com"
  """
  @spec init(keyword()) :: Config.t()
  def init(opts) when is_list(opts) do
    {rejections, mpp_opts} = Keyword.pop(opts, :rejections)

    # `:capabilities` is read at macro-expansion time by `use ApiToolkit.MCP`.
    # Dropping it here keeps a future MPP option of the same name from silently
    # picking up an MCP capability map.
    mpp_opts = Keyword.delete(mpp_opts, :capabilities)

    %Config{mpp: MPP.Mcp.init(mpp_opts), rejections: rejections}
  end

  @doc """
  Runs a `tools/call` through MPP payment verification when the tool is paid.

  `run_tool` is a zero-arity thunk returning the formatted MCP tool result map.
  It is invoked by MPP only after a credential verifies; on the free path the
  caller invokes it instead.

  Returns:

    * `:free` — tool is not gated, caller runs it
    * `{:ok, result}` — payment verified, result carries the receipt
    * `{:error, code, message, data}` — JSON-RPC error parts for the caller
      to wrap in its own envelope
  """
  @spec gate_tool_call(String.t(), map(), module(), Config.t(), (-> map())) ::
          :free | {:ok, map()} | {:error, integer(), String.t(), map()}
  def gate_tool_call(name, message, handler, %Config{} = config, run_tool) when is_function(run_tool, 0) do
    if requires_payment?(name, handler) do
      message
      |> MPP.Mcp.call(config.mpp, fn _request -> %{"result" => run_tool.()} end)
      |> to_gate_result(config, name)
    else
      :free
    end
  end

  # Wrapping the tool result in an explicit single-key "result" map is
  # load-bearing: a tool returning a map that happens to carry a "result" or
  # "error" string key would otherwise be mistaken for a JSON-RPC envelope by
  # MPP.Transports.JsonRpc.Adapter.wrap_handler_response/2, producing a
  # malformed response and silently dropping the receipt for a payment that
  # was already consumed.
  defp to_gate_result(%{"result" => result}, _config, _name), do: {:ok, result}

  defp to_gate_result(%{"error" => %{"code" => code, "message" => message, "data" => data}}, config, name) do
    record_rejection(config, rejection_type(data), name)
    {:error, code, message, data}
  end

  @doc """
  Returns `true` when a tool requires payment.

  Looks the tool up in the handler's `dispatch_map/0` and treats the `:paid`
  tier as gated. **Fails closed**: a handler that doesn't export
  `dispatch_map/0`, or whose map omits the tool, has it treated as paid. A tool
  is served for free only on an explicit non-`:paid` tier, so a hand-written
  `MCP.Server` implementation can't accidentally give paid tools away.
  """
  @spec requires_payment?(String.t(), module()) :: boolean()
  def requires_payment?(name, handler) do
    if Code.ensure_loaded(handler) == {:module, handler} and
         function_exported?(handler, :dispatch_map, 0) do
      case handler.dispatch_map() do
        %{^name => {_mod, _fun, :paid}} -> true
        %{^name => {_mod, _fun, _other_tier}} -> false
        _ -> true
      end
    else
      true
    end
  end

  @doc """
  Returns MCP-wire challenge maps for every configured payment method.

  Useful for advertising prices outside a 402 — discovery documents, pricing
  endpoints — and for building credentials in tests.
  """
  @spec generate_challenges(Config.t()) :: [map()]
  def generate_challenges(%Config{mpp: mpp}) do
    # MPP.Mcp.challenge_to_map/1 is private and MPP.Plug.generate_challenge/2 is
    # @doc false, so the error builder is the only public route from a config to
    # MCP-wire challenge maps. Tracked upstream as a request for
    # MPP.Mcp.generate_challenges/1.
    mpp.method_entries
    |> Enum.map(&MPP.Plug.generate_challenge(mpp, &1))
    |> MPP.Mcp.payment_required_error()
    |> get_in(["data", "challenges"])
  end

  @doc """
  Returns the payment capability map for the MCP `initialize` response.

  ## Examples

      iex> config = ApiToolkit.MCP.Payment.init(
      ...>   secret_key: "s3cret",
      ...>   realm: "api.example.com",
      ...>   method: ApiToolkit.TestPaymentMethod,
      ...>   amount: "1000",
      ...>   currency: "usd"
      ...> )
      iex> ApiToolkit.MCP.Payment.capabilities(config)
      %{experimental: %{payment: %{methods: %{"test" => %{intents: ["charge"]}}}}}
  """
  @spec capabilities(Config.t()) :: map()
  def capabilities(%Config{mpp: mpp}) do
    methods =
      Map.new(mpp.method_entries, fn entry ->
        {entry.method.method_name(), %{intents: [mpp.intent]}}
      end)

    %{experimental: %{payment: %{methods: methods}}}
  end

  # --- Private: rejection recording ---

  defp record_rejection(%Config{rejections: nil}, _type, _name), do: :ok

  defp record_rejection(%Config{rejections: rejections}, type, name) do
    ApiToolkit.Rejections.record(rejections, type, name)
    :ok
  rescue
    # Rejections.record/3 writes straight to a named ETS table and raises when
    # the tracker isn't started. Observability must never turn a payment
    # rejection into a 500.
    ArgumentError -> :ok
  end

  # error.data.problem.type is an RFC 9457 URI, e.g.
  # "https://paymentauth.org/problems/malformed-credential". MPP defines ~25 of
  # them across two base URIs, so match the suffix and collapse to the three
  # buckets ApiToolkit.Rejections reports at rather than enumerating a list that
  # needs a bump every time MPP adds a problem type.
  defp rejection_type(%{"problem" => %{"type" => type}}) when is_binary(type) do
    type |> String.split("/") |> List.last() |> problem_suffix_to_type()
  end

  defp rejection_type(_data), do: :verification_failed

  defp problem_suffix_to_type("payment-required"), do: :payment_required
  defp problem_suffix_to_type("malformed-credential"), do: :malformed_credential
  defp problem_suffix_to_type(_other), do: :verification_failed
end
