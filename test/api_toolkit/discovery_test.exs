defmodule ApiToolkit.DiscoveryTest do
  use ExUnit.Case, async: true

  describe "providers/0" do
    test "returns all providers" do
      providers = ApiToolkit.TestDiscovery.providers()

      assert is_list(providers)
      assert length(providers) == 2

      provider_names = Enum.map(providers, & &1.name)
      assert "Test API" in provider_names
      assert "Other API" in provider_names
    end

    test "each provider has required fields" do
      for provider <- ApiToolkit.TestDiscovery.providers() do
        assert Map.has_key?(provider, :name)
        assert Map.has_key?(provider, :description)
        assert Map.has_key?(provider, :rate_limit)
        assert Map.has_key?(provider, :cache_ttl_ms)
        assert Map.has_key?(provider, :module)
        assert is_atom(provider.module)
      end
    end
  end

  describe "all_endpoints/0" do
    test "returns endpoints from all providers" do
      endpoints = ApiToolkit.TestDiscovery.all_endpoints()

      assert is_list(endpoints)
      # TestProvider has 2 endpoints, OtherTestProvider has 1
      assert length(endpoints) == 3
    end

    test "each endpoint has required fields" do
      for endpoint <- ApiToolkit.TestDiscovery.all_endpoints() do
        assert Map.has_key?(endpoint, :function)
        assert Map.has_key?(endpoint, :path)
        assert Map.has_key?(endpoint, :method)
        assert Map.has_key?(endpoint, :description)
        assert Map.has_key?(endpoint, :params)
        assert Map.has_key?(endpoint, :errors)
        assert Map.has_key?(endpoint, :provider)
      end
    end
  end

  describe "describe/1" do
    test "returns endpoint info for valid path" do
      info = ApiToolkit.TestDiscovery.describe("/test/search")

      assert info.function == :search
      assert info.path == "/test/search"
      assert is_list(info.params)
    end

    test "returns nil for invalid path" do
      assert ApiToolkit.TestDiscovery.describe("/nonexistent/path") == nil
    end
  end

  describe "help/0" do
    test "returns a formatted help string" do
      help = ApiToolkit.TestDiscovery.help()

      assert is_binary(help)
      assert help =~ "Available API Endpoints"
      assert help =~ "/test/search"
      assert help =~ "/other/list"
    end

    test "uses caller module name, not hardcoded" do
      help = ApiToolkit.TestDiscovery.help()

      assert help =~ "ApiToolkit.TestDiscovery"
      refute help =~ "ApiCache.Discovery"
    end
  end

  describe "by_provider/0" do
    test "groups endpoints by provider name" do
      grouped = ApiToolkit.TestDiscovery.by_provider()

      assert is_map(grouped)
      assert Map.has_key?(grouped, "Test API")
      assert Map.has_key?(grouped, "Other API")

      assert length(grouped["Test API"]) == 2
      assert length(grouped["Other API"]) == 1
    end
  end

  describe "search/1" do
    test "finds endpoints by path keyword" do
      results = ApiToolkit.TestDiscovery.search("search")

      assert results != []
      paths = Enum.map(results, & &1.path)
      assert "/test/search" in paths
    end

    test "finds endpoints by description keyword" do
      results = ApiToolkit.TestDiscovery.search("List")

      assert results != []
      assert Enum.any?(results, &(&1.path == "/other/list"))
    end

    test "is case insensitive" do
      results_lower = ApiToolkit.TestDiscovery.search("search")
      results_upper = ApiToolkit.TestDiscovery.search("SEARCH")

      assert results_lower == results_upper
    end

    test "returns empty list for no matches" do
      results = ApiToolkit.TestDiscovery.search("zzznomatch")
      assert results == []
    end
  end

  describe "categories/0" do
    test "returns all unique categories sorted" do
      categories = ApiToolkit.TestDiscovery.categories()

      assert is_list(categories)
      assert categories == Enum.sort(categories)
    end
  end

  describe "by_category/1" do
    test "returns endpoints matching category" do
      results = ApiToolkit.TestDiscovery.by_category(:web)

      assert is_list(results)

      for endpoint <- results do
        assert :web in (endpoint.categories || [])
      end
    end

    test "returns empty list for unknown category" do
      results = ApiToolkit.TestDiscovery.by_category(:nonexistent_category)
      assert results == []
    end
  end
end
