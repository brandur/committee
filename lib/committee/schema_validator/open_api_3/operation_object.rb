module Committee
  class SchemaValidator::OpenAPI3::OperationObject
    # TODO: anyOf support

    # @param oas_parser_endpoint [OasParser::Endpoint]
    def initialize(oas_parser_endpoint)
      @oas_parser_endpoint = oas_parser_endpoint
    end

    def coerce_query_parameter_object(name, value)
      query_parameter_object = query_parameters[name]
      return [nil, false] unless query_parameter_object

      coerce_value(value, query_parameter_object)
    end

    def validate_request_params(params)
      err = case oas_parser_endpoint.method
            when 'get'
              # TODO: get validation support
            when 'post'
              validate_post_request_params(params)
            when 'put'
              validate_post_request_params(params)
            when 'patch'
              validate_post_request_params(params)
              #when 'delete'
              # TODO: delete validation support
            else
              raise "OpenAPI3 not support #{oas_parser_endpoint.method} method"
            end
      raise err if err
    end

    def validate_response_params(status, content_type, data)
      ro = response_object(status)
      media_type_object = ro.content[content_type] # TODO: support media type range like `text/*` because it's OpenAPI3 definition
      return unless media_type_object # TODO: raise error option

      # media_type_object like {schema: {type: 'object', properties: {....}}}
      # OasParser::Parameter check root hash 'properties' so we should flatten.
      # But, array object 'items' properties check ['schema']['items'] so we mustn't flatten :(
      media_type_object = media_type_object['schema'] if media_type_object['schema'] && media_type_object['schema']['type'] == 'object'
      parameter = OasParser::Parameter.new(ro, media_type_object)

      error = check_parameter_type('response', data, parameter)
      raise error if error
    end

    private

    # @return [OasParser::Endpoint]
    attr_reader :oas_parser_endpoint

    def validate_post_request_params(params)
      params.each do |name, value|
        parameter = request_body_properties[name]
        err = check_parameter_type(name, value, parameter)
        return err if err
      end

      nil
    end

    def check_parameter_type(name, value, parameter)
      return unless parameter # not definition in OpenAPI3

      if value.nil?
        return if parameter.raw["nullable"]

        return InvalidRequest.new("invalid parameter type #{name} #{value} #{value.class} #{parameter.type}")
      end

      case parameter.type
      when "string"
        return string_check(name, value, parameter) if value.is_a?(String)
      when "integer"
        return integer_check(name, value, parameter) if value.is_a?(Integer)
      when "boolean"
        return if value.is_a?(TrueClass)
        return if value.is_a?(FalseClass)
      when "number"
        return integer_check(name, value, parameter) if value.is_a?(Integer)
        return number_check(name, value, parameter) if value.is_a?(Numeric)
      when "object"
        return validate_object(name, value, parameter) if value.is_a?(Hash)
      when "array"
        return validate_array(name, value, parameter) if value.is_a?(Array)
      else
        # TODO: unknown type support
      end

      InvalidRequest.new("invalid parameter type #{name} #{value} #{value.class} #{parameter.type}")
    end

    def number_check(name, value, parameter)
      check_enum_include(name, value, parameter)
    end

    def integer_check(name, value, parameter)
      check_enum_include(name, value, parameter)
    end

    def string_check(name, value, parameter)
      check_enum_include(name, value, parameter)
    end

    def check_enum_include(name, value, parameter)
      return unless parameter.enum
      return if parameter.enum.include?(value)

      InvalidRequest.new("Invalid parameter #{name} #{value} isn't in enum")
    end

    # @param [OasParser::Parameter] parameter parameter.type = array
    # @param [Array<Object>] values
    def validate_array(object_name, values, parameter)
      is_any_of = parameter.items['anyOf']

      items = if is_any_of
                parameter.items['anyOf'].map{ |item| OasParser::Parameter.new(parameter, item) }
              else
                [OasParser::Parameter.new(parameter, parameter.items)] # TODO: multi pattern items support (allOf)
              end

      values.each do |v|
        if is_any_of
          next if items.any? { |item| check_parameter_type(object_name, v, item).nil? }
          return InvalidRequest.new("Invalid parameter #{v} isn't any of #{items}")
        else
          err = check_parameter_type(object_name, v, items.first)
          return err if err
        end
      end

      nil
    end

    def validate_object(_object_name, values, parameter)
      properties_hash = parameter.properties.map{ |po| [po.name, po]}.to_h
      required_set = parameter.raw['required'] ? parameter.raw['required'].to_set : Set.new

      values.each do |name, value|
        parameter = properties_hash[name]
        err = check_parameter_type(name, value, parameter)
        return err if err

        required_set.delete(name)
      end

      return InvalidRequest.new("required parameters #{required_set.to_a.join(",")} not exist") unless required_set.empty?
      nil
    end

    def request_body_properties
      # TODO: use original format
      @request_body_properties ||= oas_parser_endpoint.request_body.properties_for_format('application/json').map{ |po| [po.name, po]}.to_h
    end

    def query_parameters
      @query_parameters ||= oas_parser_endpoint.query_parameters.map{ |parameter| [parameter.name, parameter] }.to_h
    end

    def coerce_value(value, query_parameter_object)
      return [nil, false] unless value

      schema = query_parameter_object.schema
      return [value, false] unless schema

      case schema["type"]
      when "integer"
        begin
          return Integer(value), true
        rescue ArgumentError => e
          raise e unless e.message =~ /invalid value for Integer/
        end
      when "boolean"
        if value == "true" || value == "1"
          return true, true
        end
        if value == "false" || value == "0"
          return false, true
        end
      when "number"
        begin
          return Float(value), true
        rescue ArgumentError => e
          raise e unless e.message =~ /invalid value for Float/
        end
      else
        # nothing to do
      end

      return [nil, true] if schema["nullable"] && value == ""

      [nil, false]
    end

    # check responses object
    def response_object(code)
      # TODO: support error field
      # TODO: support ignore response because oas_parser ignore default and raise error
      # unless oas_parser_endpoint.raw['responses'][code] && ignore_not_exist_response_definition
      oas_parser_endpoint.response_by_code(code.to_s)
    end
  end
end