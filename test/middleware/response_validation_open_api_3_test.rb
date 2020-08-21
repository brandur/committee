# frozen_string_literal: true

require "test_helper"

describe Committee::Middleware::ResponseValidation do
  include Rack::Test::Methods

  CHARACTERS_RESPONSE = {"Otonokizaka" => ["Honoka.Kousaka"]}

  def app
    @app
  end

  it "passes through a valid response" do
    @app = new_response_rack(JSON.generate(CHARACTERS_RESPONSE), {}, schema: open_api_3_schema)
    get "/characters"
    assert_equal 200, last_response.status
  end

  it "passes through a invalid json" do
    @app = new_response_rack("not_json", {}, schema: open_api_3_schema)

    assert_raises(JSON::ParserError) do
      get "/characters"
    end
  end

  it "passes through a invalid json with parse_response_by_content_type option" do
    @app = new_response_rack("csv response", { "Content-Type" => "test/csv"}, schema: open_api_3_schema, parse_response_by_content_type: true)

    get "/csv"

    assert_equal 200, last_response.status
  end

  it "passes through not definition" do
    @app = new_response_rack(JSON.generate(CHARACTERS_RESPONSE), {}, schema: open_api_3_schema)
    get "/no_data"
    assert_equal 200, last_response.status
  end

  it "detects a response invalid due to schema" do
    @app = new_response_rack("[]", {}, schema: open_api_3_schema, raise: true)

    e = assert_raises(Committee::InvalidResponse) {
      get "/characters"
    }

    assert_match(/expected object, but received Array: /i, e.message)
  end

  it "passes through a 204 (no content) response" do
    @app = new_response_rack("", {}, {schema: open_api_3_schema}, {status: 204})
    post "/validate"
    assert_equal 204, last_response.status
  end

  it "passes through a valid response with prefix" do
    @app = new_response_rack(JSON.generate(CHARACTERS_RESPONSE), {}, schema: open_api_3_schema, prefix: "/v1")
    get "/v1/characters"
    assert_equal 200, last_response.status
  end

  it "not parameter requset" do
    @app = new_response_rack({integer: '1'}.to_json, {}, schema: open_api_3_schema, raise: true)

    assert_raises(Committee::InvalidResponse) do
      patch "/validate_no_parameter", {no_schema: 'no'}
    end
  end

  it "optionally validates non-2xx blank responses" do
    @app = new_response_rack("", {}, schema: open_api_3_schema, validate_success_only: false)
    get "/characters"
    assert_equal 200, last_response.status
  end

  describe "remote schema $ref" do
    it "passes through a valid response" do
      @app = new_response_rack(JSON.generate({ "sample" => "value" }), {}, schema: open_api_3_schema)
      get "/ref-sample"
      assert_equal 200, last_response.status
    end

    it "detects a invalid response" do
      @app = new_response_rack("{}", {}, schema: open_api_3_schema)
      get "/ref-sample"
      assert_equal 500, last_response.status
    end
  end

  describe 'check header' do
    [
      { check_header: true, description: 'valid value', header: { 'integer' => 1 }, expected: { status: 200 } },
      { check_header: true, description: 'missing value', header: { 'integer' => nil }, expected: { error: 'headers/integer/schema does not allow null values' } },
      { check_header: true, description: 'invalid value', header: { 'integer' => 'x' }, expected: { error: 'headers/integer/schema expected integer, but received String: x' } },

      { check_header: false, description: 'valid value', header: { 'integer' => 1 }, expected: { status: 200 } },
      { check_header: false, description: 'missing value', header: { 'integer' => nil }, expected: { status: 200 } },
      { check_header: false, description: 'invalid value', header: { 'integer' => 'x' }, expected: { status: 200 } },
    ].each do |h|
      check_header = h[:check_header]
      description = h[:description]
      header = h[:header]
      expected = h[:expected]
      describe "when #{check_header}" do
        %w(get post put patch delete).each do |method|
          describe method do
            describe description do
              if expected[:error].nil?
                it 'should pass' do
                  @app = new_response_rack({}.to_json, header, schema: open_api_3_schema, raise: true, check_header: check_header)

                  send(method, "/header")
                  assert_equal expected[:status], last_response.status
                end
              else
                it 'should fail' do
                  @app = new_response_rack({}.to_json, header, schema: open_api_3_schema, raise: true, check_header: check_header)

                  error = assert_raises(Committee::InvalidResponse) do
                    get "/header"
                  end
                  assert_match(expected[:error], error.message)
                end
              end
            end
          end
        end
      end
    end
  end

  describe 'validate error option' do
    it "detects an invalid response status code" do
      @app = new_response_rack({ integer: '1' }.to_json,
                               {},
                               app_status: 400,
                               schema: open_api_3_schema,
                               raise: true,
                               validate_success_only: false)


      e = assert_raises(Committee::InvalidResponse) do
        get "/characters"
      end

      assert_match(/but received String: 1/i, e.message)
    end

    it "detects an invalid response status code with validate_success_only=true" do
      @app = new_response_rack({ string_1: :honoka }.to_json,
                               {},
                               app_status: 400,
                               schema: open_api_3_schema,
                               raise: true,
                               validate_success_only: true)


      get "/characters"

      assert_equal 400, last_response.status
    end
  end

  describe ':accept_request_filter' do
    [
      { description: 'when predicate does not match, skips validation', accept_request_filter: -> (request) { request.path.start_with?('/v1/x') }, expected: { status: 200 } },
    ].each do |h|
      description = h[:description]
      accept_request_filter = h[:accept_request_filter]
      expected = h[:expected]

      it description do
        @app = new_response_rack('not_json', {}, schema: open_api_3_schema, prefix: '/v1', accept_request_filter: accept_request_filter)

        get 'v1/characters'

        assert_equal expected[:status], last_response.status
      end
    end
  end

  private

  def new_response_rack(response, headers = {}, options = {}, rack_options = {})
    # TODO: delete when 5.0.0 released because default value changed
    options[:parse_response_by_content_type] = true if options[:parse_response_by_content_type] == nil

    status = rack_options[:status] || 200
    headers = {
      "Content-Type" => "application/json"
    }.merge(headers)
    Rack::Builder.new {
      use Committee::Middleware::ResponseValidation, options
      run lambda { |_|
        [options.fetch(:app_status, status), headers, [response]]
      }
    }
  end
end
