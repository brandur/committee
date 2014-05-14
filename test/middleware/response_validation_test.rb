require_relative "../test_helper"

describe Committee::Middleware::ResponseValidation do
  include Rack::Test::Methods

  def app
    @app
  end

  it "passes through a valid response" do
    @app = new_rack_app(MultiJson.encode([ValidApp]))
    get "/apps"
    assert_equal 200, last_response.status
  end

  it "detects an invalid response" do
    @app = new_rack_app("")
    get "/apps"
    assert_equal 500, last_response.status
    assert_match /valid JSON/i, last_response.body
  end

  it "rescues JSON errors" do
    @app = new_rack_app("[{x:y}]")
    get "/apps"
    assert_equal 500, last_response.status
    assert_match /valid json/i, last_response.body
  end

  it "takes a prefix" do
    @app = new_rack_app(MultiJson.encode([ValidApp]), {}, prefix: "/v1")
    get "/v1/apps"
    assert_equal 200, last_response.status
  end

  it "warns when sending a deprecated string" do
    mock(Committee).warn_deprecated.with_any_args
    @app = new_rack_app(MultiJson.encode([ValidApp]), {},
      schema: File.read("./test/data/schema.json"))
    get "/apps"
    assert_equal 200, last_response.status
  end

  private

  def new_rack_app(response, headers = {}, options = {})
    headers = {
      "Content-Type" => "application/json"
    }.merge(headers)
    options = {
      schema: MultiJson.decode(File.read("./test/data/schema.json"))
    }.merge(options)
    Rack::Builder.new {
      use Committee::Middleware::ResponseValidation, options
      run lambda { |_|
        [200, headers, [response]]
      }
    }
  end
end
