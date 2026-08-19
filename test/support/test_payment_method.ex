defmodule ApiToolkit.TestPaymentMethod do
  @moduledoc "Stub MPP.Method for payment gating tests."

  use MPP.Method

  @impl true
  def method_name, do: "test"

  @impl true
  def verify(%{"token" => "valid"}, _charge) do
    {:ok, MPP.Receipt.new(method: "test", reference: "ref_123")}
  end

  def verify(%{"token" => "valid_ext"}, _charge) do
    {:ok, MPP.Receipt.new(method: "test", reference: "ref_456", external_id: "ext_001")}
  end

  def verify(_, _) do
    {:error, MPP.Errors.new(:verification_failed, "Invalid token")}
  end
end
