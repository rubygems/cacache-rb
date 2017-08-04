# frozen_string_literal: true

module CACache
  class Error < StandardError
  end

  class NoSuchDigestError < Error
  end
end
