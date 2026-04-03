defmodule ApiToolkit.OpenAPITest do
  use ExUnit.Case, async: true

  alias ApiToolkit.HomepageTestProvider.Discovery
  alias ApiToolkit.OpenAPI

  @opts [name: "TestAPI", version: "2.0.0"]

  describe "render/2 top-level structure" do
    test "includes openapi version 3.1.0" do
      doc = OpenAPI.render(Discovery, @opts)
      assert doc["openapi"] == "3.1.0"
    end

    test "includes info with title and version" do
      doc = OpenAPI.render(Discovery, @opts)
      assert doc["info"]["title"] == "TestAPI"
      assert doc["info"]["version"] == "2.0.0"
    end

    test "includes paths for all endpoints" do
      doc = OpenAPI.render(Discovery, @opts)
      assert Map.has_key?(doc["paths"], "/api/encode")
      assert Map.has_key?(doc["paths"], "/api/batch")
      assert Map.has_key?(doc["paths"], "/api/status")
    end

    test "returns a JSON-serializable map" do
      doc = OpenAPI.render(Discovery, @opts)
      assert {:ok, json} = Jason.encode(doc)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["openapi"] == "3.1.0"
    end
  end

  describe "render/2 optional info fields" do
    test "includes description when provided" do
      opts = @opts ++ [description: "A test API."]
      doc = OpenAPI.render(Discovery, opts)
      assert doc["info"]["description"] == "A test API."
    end

    test "excludes description when not provided" do
      doc = OpenAPI.render(Discovery, @opts)
      refute Map.has_key?(doc["info"], "description")
    end

    test "includes contact when provided" do
      opts = @opts ++ [contact: %{name: "Support", url: "https://example.com"}]
      doc = OpenAPI.render(Discovery, opts)
      assert doc["info"]["contact"]["name"] == "Support"
      assert doc["info"]["contact"]["url"] == "https://example.com"
    end

    test "includes license when provided" do
      opts = @opts ++ [license: %{name: "MIT", url: "https://opensource.org/licenses/MIT"}]
      doc = OpenAPI.render(Discovery, opts)
      assert doc["info"]["license"]["name"] == "MIT"
    end
  end

  describe "render/2 servers" do
    test "includes servers array when url provided" do
      opts = @opts ++ [url: "https://api.example.com"]
      doc = OpenAPI.render(Discovery, opts)
      assert [%{"url" => "https://api.example.com"}] = doc["servers"]
    end

    test "excludes servers when url not provided" do
      doc = OpenAPI.render(Discovery, @opts)
      refute Map.has_key?(doc, "servers")
    end
  end

  describe "render/2 GET endpoint" do
    test "renders query parameters with schema and metadata" do
      doc = OpenAPI.render(Discovery, @opts)
      operation = doc["paths"]["/api/encode"]["get"]

      assert operation["summary"] == "Encode a value"
      assert operation["operationId"] == "encode"

      [param] = operation["parameters"]
      assert param["name"] == "value"
      assert param["in"] == "query"
      assert param["required"] == true
      assert param["schema"] == %{"type" => "string"}
      assert param["description"] == "Value to encode"
      assert param["example"] == "0xff"
    end

    test "includes 200 response" do
      doc = OpenAPI.render(Discovery, @opts)
      operation = doc["paths"]["/api/encode"]["get"]
      assert operation["responses"]["200"]["description"] == "Successful response"
    end

    test "GET endpoint without params has no parameters key" do
      doc = OpenAPI.render(Discovery, @opts)
      operation = doc["paths"]["/api/status"]["get"]

      refute Map.has_key?(operation, "parameters")
      refute Map.has_key?(operation, "requestBody")
    end
  end

  describe "render/2 POST endpoint" do
    test "renders requestBody with JSON schema" do
      doc = OpenAPI.render(Discovery, @opts)
      operation = doc["paths"]["/api/batch"]["post"]

      assert operation["summary"] == "Batch operation"
      assert operation["operationId"] == "batch"
      refute Map.has_key?(operation, "parameters")

      body = operation["requestBody"]
      assert body["required"] == true

      schema = body["content"]["application/json"]["schema"]
      assert schema["type"] == "object"
      assert schema["properties"]["items"]["type"] == "string"
      assert "items" in schema["required"]
    end

    test "POST requestBody omits required array when no params are required" do
      defmodule OptionalPostProvider do
        @moduledoc false
        use ApiToolkit.Provider,
          name: "OptionalPost",
          description: "Provider with optional POST params",
          rate_limit: nil,
          cache_ttl_ms: 60_000

        defapi(:update,
          path: "/api/update",
          method: :post,
          description: "Update something",
          params: [
            %{name: "note", type: :string, required: false, description: "Optional note"}
          ]
        )

        def update(_params), do: {:ok, %{}, 60_000}

        defmodule Discovery do
          @moduledoc false
          use ApiToolkit.Discovery, providers: [OptionalPostProvider]
        end
      end

      doc = OpenAPI.render(OptionalPostProvider.Discovery, @opts)
      schema = doc["paths"]["/api/update"]["post"]["requestBody"]["content"]["application/json"]["schema"]

      refute Map.has_key?(schema, "required")
    end
  end

  describe "render/2 type mapping" do
    test "maps all supported param types to correct JSON Schema" do
      defmodule TypesProvider do
        @moduledoc false
        use ApiToolkit.Provider,
          name: "Types",
          description: "Provider with all param types",
          rate_limit: nil,
          cache_ttl_ms: 60_000

        defapi(:multi,
          path: "/api/multi",
          method: :post,
          description: "Multi-type endpoint",
          params: [
            %{name: "text", type: :string, required: true, description: "A string"},
            %{name: "count", type: :integer, required: false, description: "An integer"},
            %{name: "ratio", type: :float, required: false, description: "A float"},
            %{name: "flag", type: :boolean, required: false, description: "A boolean"},
            %{name: "tags", type: :array, required: false, description: "An array"}
          ]
        )

        def multi(_params), do: {:ok, %{}, 60_000}

        defmodule Discovery do
          @moduledoc false
          use ApiToolkit.Discovery, providers: [TypesProvider]
        end
      end

      doc = OpenAPI.render(TypesProvider.Discovery, @opts)
      props = doc["paths"]["/api/multi"]["post"]["requestBody"]["content"]["application/json"]["schema"]["properties"]

      assert props["text"] == %{"type" => "string", "description" => "A string"}
      assert props["count"] == %{"type" => "integer", "description" => "An integer"}
      assert props["ratio"] == %{"type" => "number", "description" => "A float"}
      assert props["flag"] == %{"type" => "boolean", "description" => "A boolean"}
      assert %{"type" => "array", "items" => %{"type" => "string"}, "description" => "An array"} = props["tags"]
    end
  end

  describe "render/2 pricing (x-payment-info)" do
    setup do
      pricing_fn = fn
        %{function: :encode} -> %{amount: "100", currency: "USDC", method: "tempo"}
        _ -> nil
      end

      {:ok, pricing_fn: pricing_fn}
    end

    test "adds x-payment-info to priced endpoints", %{pricing_fn: pricing_fn} do
      opts = @opts ++ [pricing: pricing_fn]
      doc = OpenAPI.render(Discovery, opts)
      operation = doc["paths"]["/api/encode"]["get"]

      assert operation["x-payment-info"] == %{
               "intent" => "charge",
               "method" => "tempo",
               "amount" => "100",
               "currency" => "USDC"
             }
    end

    test "adds 402 response to priced endpoints", %{pricing_fn: pricing_fn} do
      opts = @opts ++ [pricing: pricing_fn]
      doc = OpenAPI.render(Discovery, opts)
      operation = doc["paths"]["/api/encode"]["get"]

      assert operation["responses"]["402"]["description"] == "Payment Required"
    end

    test "non-priced endpoints have no x-payment-info or 402", %{pricing_fn: pricing_fn} do
      opts = @opts ++ [pricing: pricing_fn]
      doc = OpenAPI.render(Discovery, opts)
      operation = doc["paths"]["/api/batch"]["post"]

      refute Map.has_key?(operation, "x-payment-info")
      refute Map.has_key?(operation["responses"], "402")
    end

    test "no pricing function means no x-payment-info anywhere" do
      doc = OpenAPI.render(Discovery, @opts)

      for {_path, methods} <- doc["paths"],
          {_method, operation} <- methods do
        refute Map.has_key?(operation, "x-payment-info")
        refute Map.has_key?(operation["responses"], "402")
      end
    end
  end

  describe "render/2 x-service-info" do
    test "includes x-service-info when categories provided" do
      opts = @opts ++ [categories: ["data", "tools"]]
      doc = OpenAPI.render(Discovery, opts)
      assert doc["x-service-info"]["categories"] == ["data", "tools"]
    end

    test "includes x-service-info when docs provided" do
      opts = @opts ++ [docs: %{homepage: "https://example.com", llms: "https://example.com/llms.txt"}]
      doc = OpenAPI.render(Discovery, opts)
      assert doc["x-service-info"]["docs"]["homepage"] == "https://example.com"
      assert doc["x-service-info"]["docs"]["llms"] == "https://example.com/llms.txt"
    end

    test "includes both categories and docs when both provided" do
      opts = @opts ++ [categories: ["api"], docs: %{homepage: "https://example.com"}]
      doc = OpenAPI.render(Discovery, opts)
      assert doc["x-service-info"]["categories"] == ["api"]
      assert doc["x-service-info"]["docs"]["homepage"] == "https://example.com"
    end

    test "excludes x-service-info when neither provided" do
      doc = OpenAPI.render(Discovery, @opts)
      refute Map.has_key?(doc, "x-service-info")
    end
  end
end
