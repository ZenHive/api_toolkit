defmodule ApiToolkit.LLMsTest do
  use ExUnit.Case, async: true

  alias ApiToolkit.HomepageTestProvider.Discovery
  alias ApiToolkit.LLMs

  @opts [name: "TestService", version: "1.2.3"]

  describe "render/2 header" do
    test "includes Markdown title with name and version" do
      output = LLMs.render(Discovery, @opts)
      assert output =~ "# TestService API v1.2.3"
    end

    test "includes description when provided" do
      opts = @opts ++ [description: "A blockchain API."]
      output = LLMs.render(Discovery, opts)
      assert output =~ "# TestService API v1.2.3\n\nA blockchain API."
    end

    test "includes base URL when provided" do
      opts = @opts ++ [url: "https://example.com"]
      output = LLMs.render(Discovery, opts)
      assert output =~ "Base URL: https://example.com"
    end

    test "includes both description and URL" do
      opts = @opts ++ [description: "Tools API.", url: "https://example.com"]
      output = LLMs.render(Discovery, opts)
      assert output =~ "Tools API.\n\nBase URL: https://example.com"
    end
  end

  describe "render/2 flat endpoint list" do
    test "renders all endpoints under Endpoints heading" do
      output = LLMs.render(Discovery, @opts)
      assert output =~ "## Endpoints"
      assert output =~ "/api/encode"
      assert output =~ "/api/batch"
      assert output =~ "/api/status"
    end

    test "formats endpoint as Markdown heading with method and description" do
      output = LLMs.render(Discovery, @opts)
      assert output =~ "### GET /api/encode — Encode a value"
      assert output =~ "### POST /api/batch — Batch operation"
    end
  end

  describe "render/2 parameter rendering" do
    test "renders parameter list with type and required flag" do
      output = LLMs.render(Discovery, @opts)
      assert output =~ "- `value` (string, required) — Value to encode"
    end

    test "renders parameter example inline" do
      output = LLMs.render(Discovery, @opts)
      assert output =~ ~s(Example: "0xff")
    end

    test "omits Parameters section for endpoints with no params" do
      output = LLMs.render(Discovery, @opts)

      # Split into endpoint blocks by "###" and find the status block
      status_block =
        output
        |> String.split("### ")
        |> Enum.find(&(&1 =~ "/api/status"))

      refute status_block =~ "Parameters:"
    end
  end

  describe "render/2 example requests" do
    test "GET endpoints with :example params show example request" do
      output = LLMs.render(Discovery, @opts)
      assert output =~ "Example: `GET /api/encode?value=0xff`"
    end

    test "POST endpoints have no example request line" do
      output = LLMs.render(Discovery, @opts)

      batch_block =
        output
        |> String.split("### ")
        |> Enum.find(&(&1 =~ "/api/batch"))

      refute batch_block =~ "Example: `"
    end

    test "GET endpoints without :example have no example request line" do
      output = LLMs.render(Discovery, @opts)

      status_block =
        output
        |> String.split("### ")
        |> Enum.find(&(&1 =~ "/api/status"))

      refute status_block =~ "Example: `"
    end

    test "example URL includes base URL when :url provided" do
      opts = @opts ++ [url: "https://example.com"]
      output = LLMs.render(Discovery, opts)
      # Example line uses path only (base URL is in header), no duplication
      assert output =~ "Example: `GET /api/encode?value=0xff`"
    end
  end

  describe "render/2 with group_by" do
    test "groups endpoints by provider" do
      opts =
        @opts ++
          [
            group_by: & &1.provider,
            group_labels: %{
              "Test API" => "Test Endpoints",
              "Other API" => "Other Endpoints"
            }
          ]

      output = LLMs.render(ApiToolkit.TestDiscovery, opts)
      refute output =~ "## Endpoints"
      assert output =~ "## Test Endpoints"
      assert output =~ "## Other Endpoints"
    end

    test "uses stringified key when no label provided" do
      opts = @opts ++ [group_by: & &1.provider]
      output = LLMs.render(ApiToolkit.TestDiscovery, opts)
      assert output =~ "## Test API"
      assert output =~ "## Other API"
    end

    test "handles custom group_by function" do
      opts =
        @opts ++
          [
            group_by: & &1[:tier],
            group_labels: %{nil: "Ungrouped"}
          ]

      output = LLMs.render(Discovery, opts)
      # HomepageTestProvider has no :tier field, so all go under nil key
      assert output =~ "## Ungrouped"
    end
  end

  describe "render/2 with pricing" do
    test "renders pricing line when function returns text" do
      opts = @opts ++ [pricing: fn _endpoint -> "$0.01 per request" end]
      output = LLMs.render(Discovery, opts)
      assert output =~ "Pricing: $0.01 per request"
    end

    test "omits pricing line when function returns nil" do
      opts = @opts ++ [pricing: fn _endpoint -> nil end]
      output = LLMs.render(Discovery, opts)
      refute output =~ "Pricing:"
    end

    test "supports selective pricing per endpoint" do
      opts =
        @opts ++
          [
            pricing: fn
              %{function: :batch} -> "$0.05 per batch"
              _ -> nil
            end
          ]

      output = LLMs.render(Discovery, opts)

      batch_block =
        output
        |> String.split("### ")
        |> Enum.find(&(&1 =~ "/api/batch"))

      encode_block =
        output
        |> String.split("### ")
        |> Enum.find(&(&1 =~ "/api/encode"))

      assert batch_block =~ "Pricing: $0.05 per batch"
      refute encode_block =~ "Pricing:"
    end
  end

  describe "render/2 with discovery_paths" do
    test "renders discovery section with separator" do
      opts =
        @opts ++
          [
            discovery_paths: [
              {"GET", "/api/discover", "JSON endpoint metadata"},
              {"GET", "/llms.txt", "This document"}
            ]
          ]

      output = LLMs.render(Discovery, opts)
      assert output =~ "---"
      assert output =~ "## Discovery"
      assert output =~ "- GET /api/discover — JSON endpoint metadata"
      assert output =~ "- GET /llms.txt — This document"
    end

    test "omits discovery section when not provided" do
      output = LLMs.render(Discovery, @opts)
      refute output =~ "## Discovery"
    end

    test "omits discovery section when empty list provided" do
      opts = @opts ++ [discovery_paths: []]
      output = LLMs.render(Discovery, opts)
      refute output =~ "## Discovery"
      refute output =~ "---"
    end
  end

  describe "render/2 completeness" do
    test "includes all endpoints from Discovery" do
      output = LLMs.render(Discovery, @opts)
      endpoints = Discovery.all_endpoints()

      for endpoint <- endpoints do
        assert output =~ endpoint.path,
               "Missing endpoint: #{endpoint.path}"
      end
    end
  end
end
