defmodule ApiToolkit.RateLimiter do
  @moduledoc """
  Token bucket rate limiter GenServer.

  Supports configurable rate limits per named instance.

  ## Usage

  Add to your supervision tree:

      children = [
        {ApiToolkit.RateLimiter, name: MyApp.RateLimiter.ServiceA, rate: {1, :second}},
        {ApiToolkit.RateLimiter, name: MyApp.RateLimiter.ServiceB, rate: {25, :day}}
      ]

  Then acquire tokens before making requests:

      ApiToolkit.RateLimiter.acquire(MyApp.RateLimiter.ServiceA)
  """
  use GenServer
  use Descripex, namespace: "/rate-limiter"

  alias ApiToolkit.Internal.ChildSpec

  defstruct [:tokens, :max_tokens, :refill_ms, :waiting]

  @type t :: %__MODULE__{
          # Client API
          tokens: non_neg_integer(),
          max_tokens: pos_integer(),
          refill_ms: pos_integer(),
          waiting: :queue.queue()
        }

  @doc """
  Returns a child specification for supervision.

  Uses the `:name` option as the unique child id.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    ChildSpec.build(__MODULE__, Keyword.fetch!(opts, :name), opts)
  end

  @doc """
  Starts a rate limiter with the given name and rate configuration.

  ## Options

  - `:name` - Required. The GenServer name
  - `:rate` - Required. Tuple of `{count, period}` where period is `:second`, `:minute`, or `:day`
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  api(:acquire, "Acquire a token from the rate limiter. Blocks until a token is available if the bucket is empty.",
    params: [
      server: [kind: :config, description: "The rate limiter name or pid"]
    ],
    returns: %{type: :ok, description: "Returns :ok once a token is acquired"}
  )

  @spec acquire(GenServer.server()) :: :ok
  def acquire(server) do
    GenServer.call(server, :acquire, :infinity)
  end

  api(:status, "Return the current status of the rate limiter without consuming a token.",
    # Server callbacks
    params: [
      server: [kind: :config, description: "The rate limiter name or pid"]
    ],
    returns: %{
      type: :map,
      description: "Map with :tokens_available, :max_tokens, and :queue_depth keys"
    }
  )

  @spec status(GenServer.server()) :: map()
  def status(server) do
    GenServer.call(server, :status)
  end

  @impl true
  def init(opts) do
    {count, period} = Keyword.fetch!(opts, :rate)
    refill_ms = period_to_ms(period)

    state = %__MODULE__{
      tokens: count,
      max_tokens: count,
      refill_ms: refill_ms,
      waiting: :queue.new()
    }

    schedule_refill(refill_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:acquire, from, %__MODULE__{} = state) do
    if state.tokens > 0 do
      {:reply, :ok, %{state | tokens: state.tokens - 1}}
    else
      waiting = :queue.in(from, state.waiting)
      {:noreply, %{state | waiting: waiting}}
    end
  end

  # Private functions

  @impl true
  def handle_call(:status, _from, %__MODULE__{} = state) do
    status = %{
      tokens_available: state.tokens,
      max_tokens: state.max_tokens,
      queue_depth: :queue.len(state.waiting)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info(:refill, %__MODULE__{} = state) do
    state = refill_tokens(state)
    schedule_refill(state.refill_ms)
    {:noreply, state}
  end

  defp period_to_ms(:second), do: 1_000
  defp period_to_ms(:minute), do: 60_000
  defp period_to_ms(:day), do: 86_400_000

  defp schedule_refill(refill_ms) do
    Process.send_after(self(), :refill, refill_ms)
  end

  # Adds one token (up to max) and serves any waiting callers FIFO
  defp refill_tokens(%__MODULE__{} = state) do
    new_tokens = min(state.tokens + 1, state.max_tokens)
    {state, new_tokens} = maybe_serve_waiting(state, new_tokens)
    %{state | tokens: new_tokens}
  end

  # Replies to queued callers while tokens remain
  defp maybe_serve_waiting(%__MODULE__{} = state, tokens) when tokens > 0 do
    case :queue.out(state.waiting) do
      {{:value, from}, waiting} ->
        GenServer.reply(from, :ok)
        maybe_serve_waiting(%{state | waiting: waiting}, tokens - 1)

      {:empty, _} ->
        {state, tokens}
    end
  end

  defp maybe_serve_waiting(%__MODULE__{} = state, tokens), do: {state, tokens}
end
