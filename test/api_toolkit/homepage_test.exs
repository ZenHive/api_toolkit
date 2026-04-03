defmodule ApiToolkit.HomepageTest do
  use ExUnit.Case, async: true

  alias ApiToolkit.Homepage
  alias ApiToolkit.HomepageTestProvider.Discovery

  @opts [name: "TestService", version: "1.2.3"]

  describe "render/2 with flat list (no group_by)" do
    test "includes name and version in header" do
      output = Homepage.render(ApiToolkit.TestDiscovery, @opts)
      assert output =~ "TestService v1.2.3"
    end

    test "includes all endpoints under Endpoints: section" do
      output = Homepage.render(ApiToolkit.TestDiscovery, @opts)
      assert output =~ "Endpoints:"
      assert output =~ "GET /test/search"
      assert output =~ "GET /test/detail/:id"
      assert output =~ "GET /other/list"
    end

    test "formats endpoints with uppercase HTTP method" do
      output = Homepage.render(ApiToolkit.TestDiscovery, @opts)

      line =
        output
        |> String.split("\n")
        |> Enum.find(&(&1 =~ "/test/search"))

      assert line =~ "  GET /test/search"
    end
  end

  describe "render/2 with description" do
    test "includes description below header" do
      opts = @opts ++ [description: "A blockchain API."]
      output = Homepage.render(ApiToolkit.TestDiscovery, opts)
      assert output =~ "TestService v1.2.3\n\nA blockchain API."
    end
  end

  describe "render/2 with discovery_paths" do
    test "renders discovery section" do
      opts =
        @opts ++
          [
            discovery_paths: [
              {"GET", "/api/discover", "JSON endpoint metadata"},
              {"GET", "/openapi.json", "OpenAPI 3.1 spec"}
            ]
          ]

      output = Homepage.render(ApiToolkit.TestDiscovery, opts)
      assert output =~ "Discovery:"
      assert output =~ "GET /api/discover"
      assert output =~ "GET /openapi.json"
      assert output =~ "OpenAPI 3.1 spec"
    end
  end

  describe "render/2 with url footer" do
    test "renders site URL at the end" do
      opts = @opts ++ [url: "https://example.com"]
      output = Homepage.render(ApiToolkit.TestDiscovery, opts)
      assert output =~ "https://example.com"
    end

    test "omits footer when url is nil" do
      output = Homepage.render(ApiToolkit.TestDiscovery, @opts)
      lines = String.split(output, "\n")
      last_line = List.last(lines)
      refute last_line =~ "http"
    end
  end

  describe "render/2 with group_by" do
    test "groups endpoints by provider" do
      opts =
        @opts ++
          [
            group_by: & &1.provider,
            group_labels: %{"Test API" => "Test endpoints:", "Other API" => "Other endpoints:"}
          ]

      output = Homepage.render(ApiToolkit.TestDiscovery, opts)
      refute output =~ "Endpoints:"
      assert output =~ "Other endpoints:"
      assert output =~ "Test endpoints:"
    end

    test "uses stringified key when no label provided" do
      opts = @opts ++ [group_by: & &1.provider]
      output = Homepage.render(ApiToolkit.TestDiscovery, opts)
      assert output =~ "Test API:"
      assert output =~ "Other API:"
    end

    test "handles composite (tuple) group keys without crashing" do
      opts =
        @opts ++
          [
            group_by: &{&1.method, &1.provider},
            group_labels: %{{:get, "Test API"} => "Test GETs:"}
          ]

      output = Homepage.render(ApiToolkit.TestDiscovery, opts)
      assert output =~ "Test GETs:"
      # Unlabeled composite keys get inspect-style fallback
      assert output =~ "{:get, \"Other API\"}:"
    end
  end

  describe "example query strings" do
    test "GET endpoints with :example params include query string" do
      output = Homepage.render(Discovery, @opts)

      line =
        output
        |> String.split("\n")
        |> Enum.find(&(&1 =~ "/api/encode"))

      assert line =~ "?value=0xff"
    end

    test "POST endpoints render without query strings" do
      output = Homepage.render(Discovery, @opts)

      line =
        output
        |> String.split("\n")
        |> Enum.find(&(&1 =~ "/api/batch"))

      assert line =~ "POST /api/batch"
      refute line =~ "?"
    end

    test "GET endpoints with example: nil do not render bogus query params" do
      # HomepageTestProvider's :status endpoint has params: [] (no example key),
      # but this test verifies the filter handles example: nil correctly
      # by using a custom discovery module with an explicit nil example
      defmodule NilExampleProvider do
        @moduledoc false
        use ApiToolkit.Provider,
          name: "NilExample",
          description: "Provider with nil example",
          rate_limit: nil,
          cache_ttl_ms: 60_000

        defapi(:lookup,
          path: "/api/lookup",
          description: "Lookup",
          params: [
            %{name: "q", type: :string, required: true, description: "Query", example: nil}
          ]
        )

        def lookup(_params), do: {:ok, %{}, 60_000}

        defmodule Discovery do
          @moduledoc false
          use ApiToolkit.Discovery, providers: [NilExampleProvider]
        end
      end

      output = Homepage.render(NilExampleProvider.Discovery, @opts)

      line =
        output
        |> String.split("\n")
        |> Enum.find(&(&1 =~ "/api/lookup"))

      assert line == "  GET /api/lookup"
      refute line =~ "?"
    end

    test "GET endpoints without :example render without query strings" do
      output = Homepage.render(Discovery, @opts)

      line =
        output
        |> String.split("\n")
        |> Enum.find(&(&1 =~ "/api/status"))

      assert line =~ "GET /api/status"
      refute line =~ "?"
    end
  end
end
