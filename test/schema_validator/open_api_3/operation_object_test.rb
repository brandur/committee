require_relative "../../test_helper"

require "stringio"

describe Committee::SchemaValidator::OpenAPI3::OperationObject do
  describe 'validate' do
    before do
      @path = '/validate'
      @method = 'post'
      @validator_option = Committee::SchemaValidator::Option.new({}, open_api_3_schema, :open_api_3)
    end

    def operation_object
      open_api_3_schema.operation_object(@path, @method)
    end

    SCHEMA_PROPERTIES_PAIR = [
        ['string', 'str'],
        ['integer', 1],
        ['boolean', true],
        ['boolean', false],
        ['number', 0.1],
    ]

    it 'correct data' do
      operation_object.validate_request_params(SCHEMA_PROPERTIES_PAIR.to_h)
      assert true
    end

    it 'correct object data' do
      operation_object.validate_request_params({
                                     "object_1" =>
                                         {
                                             "string_1" => nil,
                                             "integer_1" => nil,
                                             "boolean_1" => nil,
                                             "number_1" => nil
                                         }
                                 })

      assert true
    end

    it 'invalid params' do
      invalids = [
          ['string', 1],
          ['string', true],
          ['string', false],
          ['string', nil],
          ['integer', '1'],
          ['integer', 0.1],
          ['integer', true],
          ['integer', false],
          ['boolean', 1],
          ['boolean', 'true'],
          ['boolean', 'false'],
          ['boolean', '0.1'],
          ['number', '0.1'],
          ['number', true],
          ['number', false],
          ['array', false],
          ['array', 1],
          ['array', true],
          ['array', '1'],
      ]

      invalids.each do |key, value|
        e = assert_raises(Committee::InvalidRequest) {
          operation_object.validate_request_params({"#{key}" => value})
        }

        assert e.message.start_with?("invalid parameter type #{key}")
      end
    end

    it 'required params' do
      object_2 = {
          "string_2" => "str",
          "integer_2" => 1,
          "boolean_2" => true,
          "number_2" => 0.1
      }

      object_2.keys.each do |key|
        deleted_object = object_2.reject{|k, _v| k == key}
        e = assert_raises(Committee::InvalidRequest) {
          operation_object.validate_request_params({"object_2" => deleted_object})
        }

        assert e.message.start_with?("required parameters #{key} not exist")
      end

      e = assert_raises(Committee::InvalidRequest) {
        operation_object.validate_request_params({"object_2" => {}})
      }

      assert e.message.start_with?("required parameters #{object_2.keys.join(",")} not exist")
    end

    it 'nested required params' do
      required_object = {
          need_object: {
              string: 'abc'
          },
          no_need_object: {
              integer: 1
          }
      }.deep_transform_keys(&:to_s)

      operation_object.validate_request_params({"required_object" => required_object})
      assert true

      required_object.delete "no_need_object"
      operation_object.validate_request_params({"required_object" => required_object})

      required_object['need_object'].delete "string"
      e = assert_raises(Committee::InvalidRequest) {
        operation_object.validate_request_params({"required_object" => required_object})
      }

      assert e.message.start_with?("required parameters string not exist")

      delete_need_object = {
          no_need_object: {
              integer: 1
          }
      }.deep_transform_keys(&:to_s)

      e = assert_raises(Committee::InvalidRequest) {
        operation_object.validate_request_params({"required_object" => delete_need_object})
      }

      assert e.message.start_with?("required parameters need_object not exist")
    end

    describe 'array' do
      it 'correct' do
        operation_object.validate_request_params({"array" => [1]})
        assert true
      end

      it 'other value include' do
        e = assert_raises(Committee::InvalidRequest) {
          operation_object.validate_request_params({"array" => [1, 1.1]})
        }

        assert e.message.start_with?("invalid parameter type array 1.1 Float integer")
      end

      it 'empty' do
        operation_object.validate_request_params({"array" => []})
        assert true
      end

      it 'nil' do
        e = assert_raises(Committee::InvalidRequest) {
          operation_object.validate_request_params({"array" => [nil]})
        }

        assert e.message.start_with?("invalid parameter type array  NilClass integer")
      end


      it 'anyOf' do
        operation_object.validate_request_params({"any_of" => ['test', true]})
        assert true

        e = assert_raises(Committee::InvalidRequest) {
          operation_object.validate_request_params({"any_of" => [1]})
        }

        assert e.message.start_with?("Invalid parameter 1 isn't any of")
      end
    end

    describe 'enum' do
      it 'enum string' do
        ['a', 'b'].each do |str|
          operation_object.validate_request_params({"enum_string" => str})
        end

        e = assert_raises(Committee::InvalidRequest) {
          operation_object.validate_request_params({"enum_string" => 'x'})
        }

        assert e.message.start_with?("Invalid parameter enum_string x isn't in enum")
      end

      it 'enum integer' do
        [1, 2].each do |n|
          operation_object.validate_request_params({"enum_integer" => n})
        end

        e = assert_raises(Committee::InvalidRequest) {
          operation_object.validate_request_params({"enum_integer" => 3})
        }

        assert e.message.start_with?("Invalid parameter enum_integer 3 isn't in enum")
      end

      it 'enum number' do
        [1.0, 2.1].each do |n|
          operation_object.validate_request_params({"enum_number" => n})
        end

        e = assert_raises(Committee::InvalidRequest) {
          operation_object.validate_request_params({"enum_number" => 1.1})
        }

        assert e.message.start_with?("Invalid parameter enum_number 1.1 isn't in enum")
      end
    end

    it 'support put method' do
      @method = "put"
      operation_object.validate_request_params({"string" => "str"})

      e = assert_raises(Committee::InvalidRequest) {
        operation_object.validate_request_params({"string" => 1})
      }

      assert e.message.start_with?("invalid parameter type string 1 Integer string")
    end

    it 'support patch method' do
      @method = "patch"
      operation_object.validate_request_params({"integer" => 1})

      e = assert_raises(Committee::InvalidRequest) {
        operation_object.validate_request_params({"integer" => "str"})
      }

      assert e.message.start_with?("invalid parameter type integer str String integer")
    end

    it 'unknown param' do
      operation_object.validate_request_params({"unknown" => 1})
    end
  end
end