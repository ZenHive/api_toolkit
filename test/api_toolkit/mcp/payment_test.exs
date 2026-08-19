defmodule ApiToolkit.MCP.PaymentTest do
  use ExUnit.Case, async: true

  alias ApiToolkit.MCP.Handler
  alias ApiToolkit.MCP.Payment
  alias ApiToolkit.MCP.Payment.Config
  alias ApiToolkit.MCP.Plug
  alias ApiToolkit.TestMCPPaymentHandler, as: PaymentHandler
  alias MPP.Client.MCP

  @secret_key "test-secret-key-for-hmac-binding"
  @realm "test.example.com"

  @valid_payment_opts [
    secret_key: @secret_key,
    realm: @realm,
    method: ApiToolkit.TestPaymentMethod,
    amount: "1000",
    currency: "usd"
  ]

  defp request(method, id, params) do
    %{"jsonrpc" => "2.0", "method" => method, "id" => id, "params" => params}
  end

  # --- init/1 ---
  # Builds a `tools/call` carrying a credential for the given challenge.
  defp paid_call(challenge, tool \\ "search", payload \\ %{"token" => "valid"}) do
    request("tools/call", 1, %{
      "name" => tool,
      "arguments" => %{"q" => "test"},
      "_meta" => %{"org.paymentauth/credential" => %{"challenge" => challenge, "payload" => payload}}
    })
  end

  defp one_challenge(config), do: hd(Payment.generate_challenges(config))

  describe "init/1" do
    test "forwards options to MPP and keeps api_toolkit extras" do
      config = Payment.init(@valid_payment_opts ++ [rejections: :my_rejections])

      assert %Config{rejections: :my_rejections} = config
      assert config.mpp.secret_key == @secret_key
      assert config.mpp.realm == @realm
      assert config.mpp.intent == "charge"
      assert [entry] = config.mpp.method_entries
      assert entry.method == ApiToolkit.TestPaymentMethod
      # MPP stores the challenge request pre-encoded as base64url(JCS(...)) —
      # the exact bytes the HMAC binds.
      assert {:ok, json} = Base.url_decode64(entry.request, padding: false)
      assert JSON.decode!(json) == %{"amount" => "1000", "currency" => "usd"}
    end

    test "defaults :rejections to nil" do
      assert %Config{rejections: nil} = Payment.init(@valid_payment_opts)
    end

    test "raises when a required option is missing" do
      assert_raise ArgumentError, fn -> Payment.init(Keyword.delete(@valid_payment_opts, :secret_key)) end
      assert_raise ArgumentError, fn -> Payment.init(Keyword.delete(@valid_payment_opts, :realm)) end
    end

    test "supports multiple payment methods" do
      config =
        Payment.init(
          secret_key: @secret_key,
          realm: @realm,
          methods: [
            [method: ApiToolkit.TestPaymentMethod, amount: "1000", currency: "usd"]
          ]
        )

      assert length(config.mpp.method_entries) == 1
    end
  end

  describe "requires_payment?/2" do
    test "returns true for paid tool" do
      assert Payment.requires_payment?("search", PaymentHandler)
    end

    test "returns true for detail (also paid)" do
      assert Payment.requires_payment?("detail", PaymentHandler)
    end

    test "returns false for free tool" do
      # --- requires_payment?/2 ---
      refute Payment.requires_payment?("list", PaymentHandler)
    end

    # Fail-closed: no tier information means the tool is not provably free.
    test "returns true for a tool absent from the dispatch map" do
      assert Payment.requires_payment?("nonexistent", PaymentHandler)
    end

    test "returns true for a handler that does not export dispatch_map/0" do
      assert Payment.requires_payment?("echo", ApiToolkit.TestMCPHandler)
      refute function_exported?(ApiToolkit.TestMCPHandler, :dispatch_map, 0)
    end
  end

  describe "generate_challenges/1" do
    test "returns one MCP-wire challenge per configured method" do
      [challenge] = Payment.generate_challenges(Payment.init(@valid_payment_opts))

      assert challenge["realm"] == @realm
      assert challenge["method"] == "test"
      assert challenge["intent"] == "charge"
      assert is_binary(challenge["id"])
      # Native JSON object on the wire — the spec forbids base64url for JSON-RPC.
      assert challenge["request"] == %{"amount" => "1000", "currency" => "usd"}
    end

    test "always carries an expiration" do
      [challenge] = Payment.generate_challenges(Payment.init(@valid_payment_opts))

      assert {:ok, _dt, _offset} = DateTime.from_iso8601(challenge["expires"])
    end

    test "includes opaque when configured" do
      # --- generate_challenges/1 ---
      [challenge] = Payment.generate_challenges(Payment.init(@valid_payment_opts ++ [opaque: "ctx"]))

      assert challenge["opaque"] == "ctx"
    end
  end

  describe "MPP interop" do
    # The regression guard for this whole refactor. The pre-MPP-0.14
    # implementation HMAC'd the raw JCS string while MPP HMACs
    # base64url(JCS(request)), so its challenges were unverifiable by every
    # other MPP SDK. This asserts the challenge is bound the way MPP expects.
    test "challenges verify against MPP.Challenge server binding" do
      %Config{mpp: mpp} = Payment.init(@valid_payment_opts)
      challenge = MPP.Plug.generate_challenge(mpp, hd(mpp.method_entries))

      assert :ok = MPP.Challenge.verify_server_binding(challenge, mpp.secret_key, mpp.realm)
    end

    test "tampering with a bound field invalidates the challenge" do
      %Config{mpp: mpp} = Payment.init(@valid_payment_opts)
      challenge = MPP.Plug.generate_challenge(mpp, hd(mpp.method_entries))

      assert {:error, :invalid_challenge} =
               MPP.Challenge.verify_server_binding(%{challenge | intent: "session"}, mpp.secret_key, mpp.realm)
    end

    # End-to-end through MPP's own MCP client: it detects -32042, selects a
    # --- MPP wire compatibility ---

    # challenge, pays, and retries with the credential in params._meta. Nothing
    # in our code shapes that exchange, so a green result proves interop.
    test "MPP.Client.MCP completes a payment against our handler" do
      assigns = %{mpp_payment: PaymentHandler.payment_config()}
      client = MCP.new(provider: {ApiToolkit.TestPaymentProvider, %{}})

      send_fun = fn req ->
        {:reply, 200, response} = Handler.handle(req, PaymentHandler, assigns)
        JSON.decode!(JSON.encode!(response))
      end

      msg = request("tools/call", 1, %{"name" => "search", "arguments" => %{"q" => "test"}})

      assert {:ok, response} = MCP.call(client, msg, send_fun)
      assert %{"org.paymentauth/receipt" => receipt} = response["result"]["_meta"]
      assert receipt["status"] == "success"
      assert receipt["method"] == "test"
    end
  end

  describe "capabilities/1" do
    test "advertises configured methods and the configured intent" do
      config = Payment.init(@valid_payment_opts)

      assert Payment.capabilities(config) == %{
               experimental: %{payment: %{methods: %{"test" => %{intents: ["charge"]}}}}
             }
    end
  end

  describe "gate_tool_call/5" do
    setup do
      %{config: Payment.init(@valid_payment_opts)}
    end

    test "returns :free for a free-tier tool without running the gate", %{config: config} do
      msg = request("tools/call", 1, %{"name" => "list"})

      assert :free = Payment.gate_tool_call("list", msg, PaymentHandler, config, fn -> %{ran: true} end)
    end

    test "returns a -32042 error for a paid tool without a credential", %{config: config} do
      msg = request("tools/call", 1, %{"name" => "search"})

      assert {:error, -32_042, "Payment Required", data} =
               Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{ran: true} end)

      assert data["httpStatus"] == 402
      assert [%{"realm" => @realm} | _] = data["challenges"]
      assert data["problem"]["type"] =~ "payment-required"
    end

    test "does not invoke the tool when payment is missing", %{config: config} do
      msg = request("tools/call", 1, %{"name" => "search"})
      me = self()

      Payment.gate_tool_call("search", msg, PaymentHandler, config, fn ->
        send(me, :tool_ran)
        %{}
      end)

      refute_received :tool_ran
    end

    test "returns {:ok, result} with a receipt for a valid credential", %{config: config} do
      msg = paid_call(one_challenge(config))

      assert {:ok, result} =
               Payment.gate_tool_call("search", msg, PaymentHandler, config, fn ->
                 %{content: [%{type: "text", text: "hi"}]}
               end)

      assert %{"org.paymentauth/receipt" => receipt} = result["_meta"]
      assert receipt["status"] == "success"
      assert receipt["reference"] == "ref_123"
      assert is_binary(receipt["challengeId"])
    end

    test "accepts a credential at the root message _meta", %{config: config} do
      challenge = one_challenge(config)

      msg =
        "tools/call"
        |> request(1, %{"name" => "search"})
        |> Map.put("_meta", %{
          "org.paymentauth/credential" => %{"challenge" => challenge, "payload" => %{"token" => "valid"}}
        })

      assert {:ok, result} = Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)
      assert result["_meta"]["org.paymentauth/receipt"]
    end

    test "returns -32043 when the payment method rejects the proof", %{config: config} do
      msg = paid_call(one_challenge(config), "search", %{"token" => "wrong"})

      assert {:error, -32_043, _message, data} =
               Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)

      assert data["problem"]["detail"] == "Invalid token"
    end

    test "returns -32602 for a structurally malformed credential", %{config: config} do
      msg =
        request("tools/call", 1, %{
          "name" => "search",
          "_meta" => %{"org.paymentauth/credential" => %{"payload" => %{"token" => "valid"}}}
        })

      assert {:error, -32_602, _message, data} =
               Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)

      assert data["problem"]["type"] =~ "malformed-credential"
    end

    # Replay protection is new with the MPP delegation — the previous
    # hand-rolled pipeline had none, so a verified credential was reusable
    # indefinitely.
    test "rejects a credential that was already used", %{config: config} do
      msg = paid_call(one_challenge(config))

      assert {:ok, _result} = Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)

      assert {:error, -32_043, _message, data} =
               Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)

      # --- capabilities/1 ---
      assert data["problem"]["detail"] == "Payment credential already used"
    end

    # A float is outside the JCS (RFC 8785) subset MPP canonicalizes. The
    # pre-refactor encoder had no float clause and raised FunctionClauseError,
    # surfacing as a 500.
    test "rejects a JCS-incompatible credential instead of raising", %{config: config} do
      challenge = config |> one_challenge() |> Map.put("request", %{"amount" => 10.5})
      msg = paid_call(challenge)

      assert {:error, code, _message, _data} =
               Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)

      # --- gate_tool_call/5 ---

      assert code in [-32_602, -32_043]
    end
  end

  describe "rejection recording" do
    test "records payment_required against the configured tracker" do
      name = :"rejections_#{System.unique_integer([:positive])}"
      start_supervised!({ApiToolkit.Rejections, name: name})
      config = Payment.init(@valid_payment_opts ++ [rejections: name])
      msg = request("tools/call", 1, %{"name" => "search"})

      Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)

      assert [{{:payment_required, "search"}, 1, _ts}] = ApiToolkit.Rejections.get_all(name)
    end

    test "records verification_failed for a rejected proof" do
      name = :"rejections_#{System.unique_integer([:positive])}"
      start_supervised!({ApiToolkit.Rejections, name: name})
      config = Payment.init(@valid_payment_opts ++ [rejections: name])
      msg = paid_call(one_challenge(config), "search", %{"token" => "wrong"})

      Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)

      assert [{{:verification_failed, "search"}, 1, _ts}] = ApiToolkit.Rejections.get_all(name)
    end

    # Observability must never turn a payment rejection into a 500.
    test "an unstarted tracker does not break the gate" do
      config = Payment.init(@valid_payment_opts ++ [rejections: :never_started_tracker])
      msg = request("tools/call", 1, %{"name" => "search"})

      assert {:error, -32_042, _message, _data} =
               Payment.gate_tool_call("search", msg, PaymentHandler, config, fn -> %{} end)
    end
  end

  describe "Handler integration" do
    setup do
      config = PaymentHandler.payment_config()
      %{assigns: %{mpp_payment: config}, config: config}
    end

    test "paid tool without credential returns -32042", %{assigns: assigns} do
      msg = request("tools/call", 1, %{"name" => "search", "arguments" => %{"q" => "test"}})

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, assigns)
      assert response.error.code == -32_042
      assert response.error.message == "Payment Required"
      assert length(response.error.data["challenges"]) == 1
    end

    test "paid tool with valid credential returns result + receipt", %{assigns: assigns, config: config} do
      msg = paid_call(one_challenge(config))

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, assigns)
      assert %{"org.paymentauth/receipt" => receipt} = response.result["_meta"]
      assert receipt["status"] == "success"
      assert response.id == 1
    end

    test "malformed credential returns -32602", %{assigns: assigns} do
      msg =
        request("tools/call", 1, %{
          "name" => "search",
          "_meta" => %{"org.paymentauth/credential" => %{"payload" => %{}}}
        })

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, assigns)
      assert response.error.code == -32_602
      assert response.error.data["problem"]["type"] =~ "malformed-credential"
    end

    # `_meta` is client-supplied and may hold any JSON value; a non-object must
    # reach the JSON-RPC error path rather than crashing the transport.
    test "non-map _meta returns an error instead of raising", %{assigns: assigns} do
      msg = request("tools/call", 1, %{"name" => "search", "_meta" => "not-a-map"})

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, assigns)
      assert response.error.code == -32_042
    end

    test "invalid credential returns -32043", %{assigns: assigns, config: config} do
      msg = paid_call(one_challenge(config), "search", %{"token" => "wrong"})

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, assigns)
      assert response.error.code == -32_043
      assert response.error.data["problem"]["detail"] == "Invalid token"
    end

    test "free tool passes through without a challenge", %{assigns: assigns} do
      msg = request("tools/call", 1, %{"name" => "list", "arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, assigns)
      assert response.result
    end

    test "no payment config in assigns means all tools pass through" do
      msg = request("tools/call", 1, %{"name" => "search", "arguments" => %{"q" => "test"}})

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, %{})
      assert response.result
    end

    # find_tool/2 runs before the gate, so an unknown tool is rejected without
    # generating a challenge or touching the replay store.
    test "unknown tool is rejected before payment", %{assigns: assigns} do
      msg = request("tools/call", 1, %{"name" => "nope", "arguments" => %{}})

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, assigns)
      assert response.error.code == -32_602
      assert response.error.message == "Tool not found"
    end

    # The credential is claimed before the tool runs, so a failing paid tool
    # still consumes payment — and still gets its receipt, so the caller keeps
    # proof of what it paid for.
    test "a paid tool that fails still receives its receipt", %{assigns: assigns, config: config} do
      msg = paid_call(one_challenge(config), "detail")

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, assigns)
      assert response.result["_meta"]["org.paymentauth/receipt"]
    end

    test "initialize includes payment capabilities" do
      msg = request("initialize", 1, %{"protocolVersion" => "2025-03-26"})

      assert {:reply, 200, response} = Handler.handle(msg, PaymentHandler, %{})
      assert response.result.capabilities.experimental.payment.methods == %{"test" => %{intents: ["charge"]}}
    end

    test "initialize merges custom :capabilities with payment capabilities" do
      msg = request("initialize", 1, %{"protocolVersion" => "2025-03-26"})

      assert {:reply, 200, response} = Handler.handle(msg, ApiToolkit.TestMCPPaymentCapsHandler, %{})
      caps = response.result.capabilities

      assert caps.logging == %{}
      assert caps.experimental.custom == %{enabled: true}
      assert caps.experimental.payment.methods == %{"test" => %{intents: ["charge"]}}
    end

    test "batch applies payment per message", %{assigns: assigns} do
      batch = [
        request("tools/call", 1, %{"name" => "search", "arguments" => %{"q" => "a"}}),
        request("tools/call", 2, %{"name" => "list", "arguments" => %{}})
      ]

      assert {:reply, 200, [paid, free]} = Handler.handle_batch(batch, PaymentHandler, assigns)
      assert paid.error.code == -32_042
      assert free.result
    end
  end

  describe "Plug auto-detection" do
    # Payment config is resolved per request, not in init/1 — a Phoenix router
    # evaluates init/1 at compile time, which would bake the secret key into the
    # router BEAM and skip gating for a not-yet-compiled handler.
    test "init/1 resolves no payment config" do
      opts = Plug.init(handler: PaymentHandler)

      refute Map.has_key?(opts.assigns, :mpp_payment)
    end

    test "auto-detects payment_config/0 and gates a paid tool" do
      conn = post_mcp(Plug.init(handler: PaymentHandler), "search")

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      # --- Rejection recording ---
      assert body["error"]["code"] == -32_042
      assert [%{"realm" => @realm} | _] = body["error"]["data"]["challenges"]
    end

    test "auto-detected config leaves free tools ungated" do
      conn = post_mcp(Plug.init(handler: PaymentHandler), "list")

      assert conn.status == 200
      assert JSON.decode!(conn.resp_body)["result"]
    end

    test "explicit :mpp_payment in assigns takes precedence" do
      opts = Plug.init(handler: PaymentHandler, assigns: %{mpp_payment: nil})
      conn = post_mcp(opts, "search")

      # nil config disables gating entirely — proof the handler's own config was not used.
      assert conn.status == 200
      assert JSON.decode!(conn.resp_body)["result"]
    end

    test "handler without payment_config gets no payment assigns" do
      opts = Plug.init(handler: ApiToolkit.TestMCPHandler)
      conn = post_mcp(opts, "echo", %{"message" => "hi"})

      assert conn.status == 200
      assert JSON.decode!(conn.resp_body)["result"]
    end
  end

  defp post_mcp(opts, tool, args \\ %{"q" => "test"}) do
    body = JSON.encode!(request("tools/call", 1, %{"name" => tool, "arguments" => args}))

    :post
    |> Elixir.Plug.Test.conn("/", body)
    # --- Handler integration ---
    |> Elixir.Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.call(opts)
  end

  # --- Plug auto-detection ---
end
