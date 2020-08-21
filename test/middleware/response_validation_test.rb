# frozen_string_literal: true

require "test_helper"

describe Committee::Middleware::ResponseValidation do
  include Rack::Test::Methods

  def app
    @app
  end

  it "passes through a valid response" do
    @app = new_rack_app(JSON.generate([ValidApp]), {}, schema: hyper_schema)
    get "/apps"
    assert_equal 200, last_response.status
  end

  it "doesn't call error_handler (has a arg) when response is valid" do
    called = false
    pr = ->(_e) { called = true }
    @app = new_rack_app(JSON.generate([ValidApp]), {}, schema: hyper_schema, error_handler: pr)
    get "/apps"
    assert !called, "error_handler is called"
  end

  it "doesn't call error_handler (has two args) when response is valid" do
    called = false
    pr = ->(_e, _env) { called = true }
    @app = new_rack_app(JSON.generate([ValidApp]), {}, schema: hyper_schema, error_handler: pr)
    get "/apps"
    assert !called, "error_handler is called"
  end

  it "detects a response invalid due to schema" do
    @app = new_rack_app("{}", {}, schema: hyper_schema)
    get "/apps"
    assert_equal 500, last_response.status
    assert_match(/{} is not an array/i, last_response.body)
  end

  it "detects a response invalid due to schema with ignore_error option" do
    @app = new_rack_app("{}", {}, schema: hyper_schema, ignore_error: true)
    get "/apps"
    assert_equal 200, last_response.status
  end

  it "detects a response invalid due to not being JSON" do
    @app = new_rack_app("{_}", {}, schema: hyper_schema)
    assert_raises(JSON::ParserError) do
      get "/apps"
    end
  end

  it "ignores a non-2xx invalid response" do
    @app = new_rack_app("[]", {}, app_status: 404, schema: hyper_schema)
    get "/apps"
    assert_equal 404, last_response.status
  end

  it "optionally validates non-2xx invalid responses" do
    @app = new_rack_app("", {}, app_status: 404, validate_success_only: false, schema: hyper_schema)
    get "/apps"
    assert_equal 500, last_response.status
    assert_match(/Invalid response/i, last_response.body)
  end

  it "passes through a 204 (no content) response" do
    @app = new_rack_app("", {}, app_status: 204, schema: hyper_schema)
    get "/apps"
    assert_equal 204, last_response.status
  end

  it "skip validation when 4xx" do
    @app = new_rack_app("[{x:y}]", {}, schema: hyper_schema, validate_success_only: true, app_status: 400)
    get "/apps"
    assert_equal 400, last_response.status
    assert_match("[{x:y}]", last_response.body)
  end

  it "calls error_handler (has a arg) when it rescues invalid response" do
    called_err = nil
    pr = ->(e) { called_err = e }
    @app = new_rack_app("{}", {}, schema: hyper_schema, error_handler: pr)
    _, err = capture_io do
      get "/apps"
    end
    assert_kind_of Committee::InvalidResponse, called_err
    assert_match(/\[DEPRECATION\]/i, err)
  end

  it "calls error_handler (has two args) when it rescues invalid response" do
    called_err = nil
    pr = ->(e, _env) { called_err = e }
    @app = new_rack_app("{}", {}, schema: hyper_schema, error_handler: pr)
    get "/apps"
    assert_kind_of Committee::InvalidResponse, called_err
  end

  it "takes a prefix" do
    @app = new_rack_app(JSON.generate([ValidApp]), {}, prefix: "/v1",
      schema: hyper_schema)
    get "/v1/apps"
    assert_equal 200, last_response.status
  end

  it "passes through a valid response for OpenAPI" do
    @app = new_rack_app(JSON.generate([ValidPet]), {},
      schema: open_api_2_schema)
    get "/api/pets"
    assert_equal 200, last_response.status
  end

  it "detects an invalid response for OpenAPI" do
    @app = new_rack_app("{_}", {}, schema: open_api_2_schema)
    assert_raises(JSON::ParserError) do
      get "/api/pets"
    end
  end

  private

  def new_rack_app(response, headers = {}, options = {})
    # TODO: delete when 5.0.0 released because default value changed
    options[:parse_response_by_content_type] = true if options[:parse_response_by_content_type] == nil

    headers = {
      "Content-Type" => "application/json"
    }.merge(headers)
    Rack::Builder.new {
      use Committee::Middleware::ResponseValidation, options
      run lambda { |_|
        [options.fetch(:app_status, 200), headers, [response]]
      }
    }
  end
end
