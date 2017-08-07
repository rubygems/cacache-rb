# frozen_string_literal: true

module CACache
  VerificationStats = Struct.new(
    :verified_content,
    :reclaimed_count,
    :reclaimed_size,
    :bad_content_count,
    :kept_size,
    :missing_content,
    :rejected_entries,
    :total_entries,
    :start_time,
    :end_time,
    :run_time
  ) do

    def without_times
      self.class.new(*to_a[0..-4])
    end

    def to_s
      "#{self.class}\n---\n" +
        to_h.map {|k, v| "#{k}: #{v}".strip unless v.nil? }.compact.sort.join("\n")
    end
  end
end
