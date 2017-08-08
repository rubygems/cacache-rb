# frozen_string_literal: true

module CACache
  # An interface to JSON that avoids requiring that gem until it's needed.
  module JSON
  module_function

    def parse(string)
      case string
      when ""
        ""
      when "{}"
        {}
      when "[]"
        []
      when "null"
        nil
      else
        require "json"
        ::JSON.parse(string)
      end
    end

    def dump(data)
      case data
      when nil
        "null"
      when {}, [], ""
        data.inspect
      else
        require "json"
        ::JSON.dump(data)
      end
    end
  end
end
