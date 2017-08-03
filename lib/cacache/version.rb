# frozen_string_literal: true

module CACache
  VERSION = "0.1.0".freeze

  CACHE_VERSION = Struct.new(:content, :index).new(2, 5).freeze
end
