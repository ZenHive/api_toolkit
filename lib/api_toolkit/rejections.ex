defmodule ApiToolkit.Rejections do
  @moduledoc """
  ETS-backed rejection counter for tracking requests rejected before dispatch.

  Tracks rejection counts by type and path. Rejection types are arbitrary atoms
  defined by the consumer (e.g., `:rate_limited`, `:payment_required`,
  `:unauthorized`). Uses atomic ETS writes — no GenServer call on the hot path.

  Complements `ApiToolkit.Metrics` (which tracks requests that reach endpoint
  functions) by measuring demand that was rejected before reaching business logic.

  ## Usage

  Add to your supervision tree:

      children = [
        ApiToolkit.Rejections
      ]

  Then record rejections from your plugs:

      ApiToolkit.Rejections.record(:rate_limited, "/api/search")
      ApiToolkit.Rejections.record(:payment_required, "/api/premium/data")

  ## Named Instances

  Run multiple independent trackers:

      children = [
        {ApiToolkit.Rejections, name: MyApp.APIRejections},
        {ApiToolkit.Rejections, name: MyApp.WebhookRejections}
      ]

      ApiToolkit.Rejections.record(MyApp.APIRejections, :rate_limited, "/api/search")
  """

  use GenServer
  use Descripex, namespace: "/rejections"

  @default_name __MODULE__

  # Position of the count field in the ETS tuple: {key, count, last_rejected_at}
  @count_pos 2

  # --- Public API ---

  @doc """
  Returns a child specification for supervision.

  Uses the `:name` option as the unique child id (defaults to `#{inspect(__MODULE__)}`).
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, @default_name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Starts the rejection tracker (creates the ETS table).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  api(:record, "Record a rejection by type and path. Atomic ETS write, sub-microsecond latency.",
    params: [
      type: [kind: :value, description: "Rejection type atom (e.g., :rate_limited, :unauthorized)"],
      path: [kind: :value, description: "The request path that was rejected"]
    ],
    returns: %{type: :ok, description: "Always returns :ok"}
  )

  @doc """
  Record a rejection. Uses the default tracker instance.

  Atomically increments the counter for the given type and path.
  """
  @spec record(atom(), String.t()) :: :ok
  def record(type, path) when is_atom(type), do: record(@default_name, type, path)

  @doc """
  Record a rejection on a named tracker instance.
  """
  @spec record(atom(), atom(), String.t()) :: :ok
  def record(server, type, path) when is_atom(type) do
    now = System.system_time(:second)
    key = {type, path}
    :ets.update_counter(server, key, {@count_pos, 1}, {key, 0, now})
    :ets.update_element(server, key, {3, now})
    :ok
  end

  api(:get_all, "Return all rejection data as raw ETS tuples.",
    returns: %{
      type: :list,
      description: "List of {{type, path}, count, last_rejected_at} tuples"
    }
  )

  @doc """
  Returns all rejection data as a list of tuples.
  """
  @spec get_all(atom()) :: [{{atom(), String.t()}, non_neg_integer(), integer()}]
  def get_all(server \\ @default_name) do
    :ets.tab2list(server)
  end

  api(:summary, "Return a summary grouped by rejection type with totals.",
    returns: %{
      type: :map,
      description: "Map with :total_rejections and per-type keys each containing :total and :by_path"
    }
  )

  @doc """
  Returns a summary grouped by rejection type with totals.

  ## Example

      %{
        total_rejections: 42,
        by_type: %{
          rate_limited: %{
            total: 30,
            by_path: %{
              "/api/search" => %{count: 20, last_rejected_at: 1711800000},
              "/api/validate" => %{count: 10, last_rejected_at: 1711800001}
            }
          },
          payment_required: %{
            total: 12,
            by_path: %{
              "/api/premium" => %{count: 12, last_rejected_at: 1711800002}
            }
          }
        }
      }

  """
  @spec summary(atom()) :: map()
  def summary(server \\ @default_name) do
    raw = get_all(server)

    by_type =
      raw
      |> Enum.group_by(fn {{type, _path}, _count, _ts} -> type end)
      |> Map.new(fn {type, rows} -> {type, build_type_summary(rows)} end)

    total = by_type |> Map.values() |> Enum.map(& &1.total) |> Enum.sum()

    %{total_rejections: total, by_type: by_type}
  end

  api(:reset, "Reset all rejection counters.", returns: %{type: :ok, description: "Always returns :ok"})

  @doc """
  Resets all rejection counters.
  """
  @spec reset(atom()) :: :ok
  def reset(server \\ @default_name) do
    :ets.delete_all_objects(server)
    :ok
  end

  # --- GenServer (table owner) ---

  @impl true
  def init(name) do
    table = :ets.new(name, [:set, :public, :named_table, write_concurrency: true])
    {:ok, table}
  end

  @impl true
  def terminate(_reason, table) do
    :ets.delete(table)
    :ok
  end

  # --- Private ---

  # Builds a summary for a single rejection type from raw ETS rows.
  defp build_type_summary(rows) do
    by_path =
      Map.new(rows, fn {{_type, path}, count, last_rejected_at} ->
        {path, %{count: count, last_rejected_at: last_rejected_at}}
      end)

    total = rows |> Enum.map(fn {_key, count, _ts} -> count end) |> Enum.sum()

    %{total: total, by_path: by_path}
  end
end
