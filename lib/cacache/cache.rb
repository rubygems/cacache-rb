# frozen_string_literal: true

module CACache
  # An on-disk cache
  class Cache
    attr_reader :cache_path

    def initialize(cache_path)
      @cache_path = cache_path
    end
  end
end
