# frozen_string_literal: true

module CACache
  Info = Struct.new(
    :key,
    :integrity,
    :path,
    :time,
    :size,
    :metadata
  ) do
    def to_json(*opts)
      to_h.to_json(*opts)
    end
  end
end
