# frozen_string_literal: true

module CACache
  class Error < StandardError
  end

  class NoSuchDigestError < Error
  end

  class ContentSizeMismatchError < Error
  end

  class IntegrityError < Error
  end
end
