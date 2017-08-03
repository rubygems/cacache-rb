# frozen_string_literal: true

module CACache
  Info = Struct.new(
    :key,
    :integrity,
    :path,
    :time,
    :size,
    :metadata
  )
end
