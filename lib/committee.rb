require "json_schema"
require "multi_json"
require "rack"

require_relative "committee/errors"
require_relative "committee/request_unpacker"
require_relative "committee/request_validator"
require_relative "committee/response_generator"
require_relative "committee/response_validator"
require_relative "committee/router"

require_relative "committee/middleware/base"
require_relative "committee/middleware/request_validation"
require_relative "committee/middleware/response_validation"
require_relative "committee/middleware/stub"

require_relative "committee/test/methods"

module Committee
  def self.warn_deprecated(message)
    if !$VERBOSE.nil?
      $stderr.puts(message)
    end
  end
end
