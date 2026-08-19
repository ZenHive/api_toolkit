defmodule ApiToolkit.TestPaymentProvider do
  @moduledoc """
  Client-side counterpart to `ApiToolkit.TestPaymentMethod`.

  Pays any `test`/`charge` challenge by echoing it back with the token the
  method accepts. Used by the interop test that drives `MPP.Client.MCP`
  against our own MCP handler, proving our challenges are consumable by MPP's
  own client.
  """

  @behaviour MPP.Client.PaymentProvider

  @impl true
  def supports?("test", "charge", _config), do: true
  def supports?(_method, _intent, _config), do: false

  @impl true
  def pay(%MPP.Challenge{} = challenge, _config) do
    {:ok, %MPP.Credential{challenge: challenge, payload: %{"token" => "valid"}}}
  end
end
