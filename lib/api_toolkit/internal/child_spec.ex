defmodule ApiToolkit.Internal.ChildSpec do
  @moduledoc false

  # RateLimiter, InboundLimiter and Rejections use their instance name as the
  # supervision child id rather than the module, so a supervisor can run
  # several instances of the same module side by side. That convention lives
  # here so the three modules agree on it; how each resolves its name (required
  # vs. defaulted) stays with the module, hence `name` is a caller argument.

  @doc """
  Builds a worker child specification whose id is the instance `name`.
  """
  @spec build(module(), term(), keyword()) :: Supervisor.child_spec()
  def build(module, name, opts) do
    %{
      id: name,
      start: {module, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end
end
