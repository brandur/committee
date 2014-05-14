require_relative "../test_helper"

describe Committee::Middleware::Stub do
  include Committee::Test::Methods
  include Rack::Test::Methods

  def app
    @app
  end

  def schema_path
    "./test/data/schema.json"
  end

  describe "#assert_schema_content_type" do
    it "passes through a valid response" do
      @app = new_rack_app(MultiJson.encode([ValidApp]))
      get "/apps"
      assert_schema_content_type
    end

    it "detects an invalid response Content-Type" do
      @app = new_rack_app(MultiJson.encode([ValidApp]), {})
      get "/apps"
      e = assert_raises(Committee::InvalidResponse) do
        assert_schema_content_type
      end
      assert_match /response header must be set to/i, e.message
    end
  end

  describe "#assert_schema_conform" do
    it "passes through a valid response" do
      @app = new_rack_app(MultiJson.encode([ValidApp]))
      get "/apps"
      assert_schema_conform
    end

    it "detects an invalid response Content-Type" do
      @app = new_rack_app(MultiJson.encode([ValidApp]), {})
      get "/apps"
      e = assert_raises(Committee::InvalidResponse) do
        assert_schema_conform
      end
      assert_match /response header must be set to/i, e.message
    end

    it "detects missing keys in response" do
      data = ValidApp.dup
      data.delete("name")
      @app = new_rack_app(MultiJson.encode([data]))
      get "/apps"
      e = assert_raises(Committee::InvalidParams) do
        assert_schema_conform
      end
      assert_equal 1, e.count
      assert_equal :missing, e.on(:name)
    end
  end

  private

  def new_rack_app(response, headers={ "Content-Type" => "application/json" })
    Rack::Builder.new {
      run lambda { |_|
        [200, headers, [response]]
      }
    }
  end
end
