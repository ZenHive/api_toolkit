defmodule ApiToolkit.ProviderTest do
  use ExUnit.Case, async: true

  alias ApiToolkit.Provider

  describe "runtime_ttl/2" do
    test "returns default when env var not set" do
      default_ttl = 300_000

      assert Provider.runtime_ttl("TEST_NONEXISTENT", default_ttl) == default_ttl
    end

    test "returns env var value when valid positive integer" do
      env_var = "TEST_TTL_VALID"
      System.put_env(env_var <> "_CACHE_TTL_MS", "60000")

      on_exit(fn -> System.delete_env(env_var <> "_CACHE_TTL_MS") end)

      assert Provider.runtime_ttl(env_var, 300_000) == 60_000
    end

    test "returns default for invalid non-numeric value" do
      env_var = "TEST_TTL_INVALID"
      System.put_env(env_var <> "_CACHE_TTL_MS", "not_a_number")

      on_exit(fn -> System.delete_env(env_var <> "_CACHE_TTL_MS") end)

      default_ttl = 300_000
      assert Provider.runtime_ttl(env_var, default_ttl) == default_ttl
    end

    test "returns default for zero value" do
      env_var = "TEST_TTL_ZERO"
      System.put_env(env_var <> "_CACHE_TTL_MS", "0")

      on_exit(fn -> System.delete_env(env_var <> "_CACHE_TTL_MS") end)

      default_ttl = 300_000
      assert Provider.runtime_ttl(env_var, default_ttl) == default_ttl
    end

    test "returns default for negative value" do
      env_var = "TEST_TTL_NEGATIVE"
      System.put_env(env_var <> "_CACHE_TTL_MS", "-1000")

      on_exit(fn -> System.delete_env(env_var <> "_CACHE_TTL_MS") end)

      default_ttl = 300_000
      assert Provider.runtime_ttl(env_var, default_ttl) == default_ttl
    end

    test "returns default for value with trailing characters" do
      env_var = "TEST_TTL_TRAILING"
      System.put_env(env_var <> "_CACHE_TTL_MS", "60000ms")

      on_exit(fn -> System.delete_env(env_var <> "_CACHE_TTL_MS") end)

      default_ttl = 300_000
      assert Provider.runtime_ttl(env_var, default_ttl) == default_ttl
    end
  end

  describe "defapi macro generates metadata" do
    test "provider_info/0 returns provider metadata" do
      info = ApiToolkit.TestProvider.provider_info()

      assert info.name == "Test API"
      assert info.description == "A test provider"
      assert info.rate_limit == "1 req/sec"
      assert is_integer(info.cache_ttl_ms)
      assert info.cache_ttl_ms > 0
    end

    test "endpoints/0 returns endpoint list" do
      endpoints = ApiToolkit.TestProvider.endpoints()

      assert is_list(endpoints)
      assert length(endpoints) == 2

      search_ep = Enum.find(endpoints, &(&1.function == :search))
      assert search_ep.path == "/test/search"
      assert search_ep.method == :get
      assert is_binary(search_ep.description)
      assert is_list(search_ep.params)
    end

    test "describe/1 returns endpoint info for valid name" do
      info = ApiToolkit.TestProvider.describe(:search)

      assert info.function == :search
      assert info.path == "/test/search"
      assert is_list(info.params)
    end

    test "describe/1 returns nil for unknown endpoint" do
      assert ApiToolkit.TestProvider.describe(:nonexistent) == nil
    end

    test "indicators/0 returns name-description pairs" do
      indicators = ApiToolkit.TestProvider.indicators()

      assert is_list(indicators)
      assert length(indicators) == 2
      assert {name, desc} = hd(indicators)
      assert is_atom(name)
      assert is_binary(desc)
    end
  end
end
