defmodule ApiToolkit.DescripexTest do
  @moduledoc false
  use ExUnit.Case, async: true

  describe "__api__/0 introspection" do
    test "Cache exposes annotated functions" do
      api = ApiToolkit.Cache.__api__()
      names = Enum.map(api, & &1.name)

      assert :get in names
      assert :put in names
      assert :delete in names
      assert :clear in names
      assert :keys in names
      assert :stats in names

      # OTP plumbing excluded
      refute :start_link in names
    end

    test "RateLimiter exposes annotated functions" do
      api = ApiToolkit.RateLimiter.__api__()
      names = Enum.map(api, & &1.name)

      assert :acquire in names
      assert :status in names
      refute :start_link in names
      refute :child_spec in names
    end

    test "InboundLimiter exposes annotated functions" do
      api = ApiToolkit.InboundLimiter.__api__()
      names = Enum.map(api, & &1.name)

      assert :check in names
      assert :status in names
      assert :reset in names
      refute :start_link in names
      refute :child_spec in names
    end

    test "Metrics exposes annotated functions" do
      api = ApiToolkit.Metrics.__api__()
      names = Enum.map(api, & &1.name)

      assert :record in names
      assert :get_all in names
      assert :summary in names
      assert :reset in names
      refute :start_link in names
    end
  end

  describe "__api__/1 function detail" do
    test "returns detail for a known function" do
      detail = ApiToolkit.Cache.__api__(:get)

      assert detail.name == :get
      assert detail.arity == 1
      assert is_binary(detail.spec)
      assert detail.hints.description =~ "cached value"
      assert is_map(detail.hints.params)
      assert Map.has_key?(detail.hints.params, :key)
    end

    test "returns nil for unknown function" do
      assert ApiToolkit.Cache.__api__(:nonexistent) == nil
    end

    test "includes returns hint when declared" do
      detail = ApiToolkit.Cache.__api__(:stats)

      assert detail.hints.returns.type == :map
      assert detail.hints.returns.description =~ "entry_count"
    end
  end

  describe "Discoverable describe/0-2" do
    test "describe/0 returns overview of all 4 modules" do
      overview = ApiToolkit.describe()

      assert length(overview) == 4

      module_names = Enum.map(overview, & &1.module)
      assert ApiToolkit.Cache in module_names
      assert ApiToolkit.RateLimiter in module_names
      assert ApiToolkit.InboundLimiter in module_names
      assert ApiToolkit.Metrics in module_names
    end

    test "describe/1 returns function list for a module by short name" do
      functions = ApiToolkit.describe(:cache)

      names = Enum.map(functions, & &1.name)
      assert :get in names
      assert :put in names
    end

    test "describe/1 returns function list for a module by full atom" do
      functions = ApiToolkit.describe(ApiToolkit.Cache)

      names = Enum.map(functions, & &1.name)
      assert :get in names
    end

    test "describe/2 returns function detail" do
      detail = ApiToolkit.describe(:cache, :get)

      assert detail.name == :get
      assert is_binary(detail.description)
    end

    test "describe/2 returns nil for unknown function" do
      assert ApiToolkit.describe(:cache, :nonexistent) == nil
    end
  end

  describe "__descripex_modules__/0" do
    test "returns the registered module list" do
      modules = ApiToolkit.__descripex_modules__()

      assert length(modules) == 4
      assert ApiToolkit.Cache in modules
    end
  end
end
