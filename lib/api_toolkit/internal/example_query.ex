defmodule ApiToolkit.Internal.ExampleQuery do
  @moduledoc false

  # Shared by Homepage and LLMs: both render an example GET request from the
  # `:example` metadata a Provider declares on its params, and both must agree
  # on which params qualify and how values are encoded.

  @doc """
  Renders `:example` param values as a query string, including the leading `?`.

  Params without an example, and list-valued examples, are skipped. Returns an
  empty string when no param qualifies.
  """
  @spec query_string([map()]) :: String.t()
  def query_string(params) do
    pairs =
      params
      |> Enum.filter(&match?(%{example: val} when val != nil and not is_list(val), &1))
      |> Enum.map(fn p -> "#{p.name}=#{URI.encode_www_form(to_string(p.example))}" end)

    case pairs do
      [] -> ""
      pairs -> "?" <> Enum.join(pairs, "&")
    end
  end
end
