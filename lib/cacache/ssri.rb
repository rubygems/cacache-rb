# frozen_string_literal: true

module CACache
  module SSRI
    SPEC_ALOGIRMTHS = %w[sha256 sha384 sha512].freeze
    SRI_PATTERN = /^([^-]+)-([^?]+)([?\S*]*)$/

    DEFAULT_PRIORITY = %w[
      md5 whirlpool sha1 sha224 sha256 sha384 sha512
    ].freeze

    class Integrity
      def initialize
        @hashes_by_algorithm = {}
      end

      def to_s(opts = {})
        sep = opts.fetch(:sep, " ")
        sep = sep.gsub(/\S+/, " ") if opts.fetch(:strict, false)

        to_h.map do |_algorith, hashes|
          hashes.map do |hash|
            hash.to_s(opts)
          end.join(sep)
        end.join(sep)
      end

      def [](algorithm)
        @hashes_by_algorithm[algorithm] || []
      end

      def add(algorithm, hash)
        (@hashes_by_algorithm[algorithm] ||= []) << hash
      end

      def to_h
        @hashes_by_algorithm
      end

      def pick_algorithm(opts = {})
        pick_algorithm = opts.fetch(:pick_algorithm, lambda {|a| DEFAULT_PRIORITY.index(a) || -1 })
        @hashes_by_algorithm.keys.max_by(&pick_algorithm)
      end

      def ==(other)
        to_s == other.to_s
      end
    end

    Hash = Struct.new(:source, :algorithm, :digest, :options)
    class Hash
      def self.create(hash, opts)
        strict = opts.fetch(:strict, false)
        source = hash.strip
        return unless match = source.match(strict ? STRICT_SRI_PATTERN : SRI_PATTERN)
        algorithm = match[1]
        return if strict && !SPEC_ALOGIRMTHS.include(match[1])
        digest = match[2]
        raw_opts = match[3]
        options = raw_opts.empty? ? [] : raw_opts[1..-1].split("?")

        new(source, algorithm, digest, options)
      end

      def hexdigest
        return unless digest
        digest.unpack("m0").first.unpack("H*").first
      end

      def to_s(opts = {})
        if opts.fetch(:strict, false)
          return "" unless SPEC_ALOGIRMTHS.include(match[1])
          return "" unless digest.match(BASE64_PATTERN)
          return "" unless options.all? {|opt| opt.match(VCHAR_PATTERN) }
        end

        opts = options && !options.empty? ? "?#{options.join("?")}" : ""

        "#{algorithm}-#{digest}#{opts}"
      end
    end

  module_function

    def parse(integrity, opts = {})
      case integrity
      when String
        _parse(integrity, opts)
      when Integrity, Hash
        _parse(integrity.to_s(opts), opts)
      else
        raise TypeError, "expected String or Integrity, got #{integrity.inspect}"
      end
    end

    def _parse(integrity, opts)
      return Hash.create(integrity, opts) if opts[:single]

      integrity.strip.split(/\s+/).reduce(Integrity.new) do |acc, string|
        next acc unless hash = Hash.create(string, opts)
        acc.add(hash.algorithm, hash) if hash.algorithm && hash.digest
        acc
      end
    end

    def from_data(data, opts = {})
      algorithms = opts.fetch(:algorithms, %w[sha512])
      opt_string = opts.fetch(:options, []).join("?")
      opt_string = "?#{opt_string}" unless opt_string.empty?

      algorithms.reduce(Integrity.new) do |acc, algo|
        digest = Digest(algo.upcase).base64digest(data)
        hash = Hash.create("#{algo}-#{digest}#{opt_string}", opts)
        acc.add(algo, hash) if hash.algorithm && hash.digest
        acc
      end
    end
  end
end
