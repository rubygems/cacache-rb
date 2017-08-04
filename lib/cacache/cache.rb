# frozen_string_literal: true

require "digest"
require "pathname"

module CACache
  # An on-disk cache
  class Cache
    include Util

    attr_reader :cache_path

    def initialize(cache_path)
      @cache_path = Pathname.new(cache_path)
    end

    # Reading

    def read(integrity, opts, &blk)
      content = pick_content_sri(integrity)
      sri = content[:sri]
      cpath = content_path(sri)
      return File.read(cpath) unless blk
      File.open(cpath, "rb", &blk)
    end
    private :read

    def has_content(integrity)
      return false unless integrity
      content = pick_content_sri(integrity)
      return false unless sri = content[:sri]
      {
        :sri => sri,
        :size => content[:stat].size,
      }
    rescue Errno::ENOENT, Errno::EPERM
      false
    end
    private :has_content

    def pick_content_sri(integrity)
      sri = SSRI.parse(integrity)
      algo = sri.pick_algorithm
      digests = sri[algo]
      cpath = content_path(digests.first)
      stat = File.lstat(cpath)
      {
        :sri => digests.first,
        :stat => stat,
      }
    end
    private :pick_content_sri

    def index_find(key)
      bucket = bucket_path(key)
      entries = bucket_entries(bucket)
      entries.reverse_each do |entry|
        return format_entry(entry) if entry["key"] == key
      end
      nil
    rescue Errno::ENOENT
      nil
    end
    private :index_find

    def ls(&blk)
      acc = {} unless blk

      recurse_children(bucket_dir, 3) do |file|
        entries = bucket_entries(file).reverse_each.reduce({}) do |a, e|
          a[e["key"]] ||= format_entry(e)
          a
        end

        if acc
          acc.merge!(entries)
        else
          entries.each_value {|v| yield(v) }
        end
      end

      acc
    end

    def get_data(by_digest, key, opts, &blk)
      entry = !by_digest && index_find(key)

      raise Errno::ENOENT, "no entry for #{key}" if !entry && !by_digest

      data = read(by_digest ? key : entry.integrity,
        :integrity => opts[:integrity],
        :size => opts.size,
        &blk)

      res = if by_digest
        data
      else
        {
          :metadata => entry.metadata,
          :data => data,
          :size => entry.size,
          :integrity => entry.integrity,
        }
      end

      # TODO: memoize

      res
    end
    private :get_data

    def get(key, opts = {})
      get_data(false, key, opts)
    end

    def get_by_digest(digest, opts = {})
      get_data(true, digest, opts)
    end

    def get_info(key, opts = {})
      # TODO: memoize
      index_find(key)
    end

    def get_has_content(integrity); end

    # Writing

    def index_insert(key, integrity, opts)
      bucket = bucket_path(key)
      entry = Info.new(key, integrity && integrity.to_s, nil, Time.now.to_i, opts[:size], opts[:metadata])
      fix_owner_mkdir_fix(bucket.dirname, opts[:uid], opts[:gid])
      require "json"
      entry_json = entry.to_h.tap {|h| h.delete(:path) }.to_json
      File.open(bucket, "a") {|f| f << "#{hash_entry(entry_json)}\t#{entry_json}\n" }
      begin
        fix_owner(bucket, opts[:uid], opts[:gid])
      rescue Errno::ENOENT
        nil
      end
      format_entry(entry)
    end
    private :index_insert

    def write(data, opts)
      size = data.length
      raise ArgumentError, "size and data length don't match" if opts.fetch(:size, size) != size
      sri = SSRI.from_data(data, opts)
      if opts[:integrity] && !SSRI.check_data(data, opts[:integrity], opts)
        raise ArgumentError, "checksum error"
      end

      mktmp(cache_path, opts) do |tmp|
        File.open(tmp, "wb") {|f| f << data }
        move_to_destination(tmp, sri, opts)
      end

      {
        :integrity => sri,
        :size => size,
      }
    end
    private :write

    def move_to_destination(tmp, sri, opts = {}, err_check = nil)
      err_check.call if err_check
      destination = content_path(sri)
      dest_dir = destination.dirname

      fix_owner_mkdir_fix(dest_dir, opts[:uid], opts[:gid])
      err_check.call if err_check

      move_file(tmp, destination)
      err_check.call if err_check

      fix_owner(destination, opts[:uid], opts[:gid])
    end
    private :move_to_destination

    def put(key, data, opts = {})
      res = write(data, opts)
      opts = opts.dup
      opts[:size] = res[:size]
      entry = index_insert(key, res[:integrity], opts)
      entry.integrity
    end

    def rm_all
      dirs = Dir[cache_path.join("*{content,index}-*")]
      FileUtils.rm_rf dirs
      nil
    end

    def rm_entry(key); end

    def rm_content(integrity); end

    # Utilities

    def clear_memoized; end

    def tmp_mkdir(opts); end

    # Integrity

    def verify(opts); end

    def verify_last_run; end

  private

    def bucket_entries(bucket)
      data = File.read(bucket, :encoding => "UTF-8")
      data.each_line.map do |line|
        hash, entry = line.chomp.split("\t", 2)
        next unless hash && entry
        next unless hash_entry(entry) == hash
        begin
          JSON.parse(entry)
        rescue
          nil
        end
      end.compact
    end

    def bucket_dir
      cache_path.join("index-v#{CACHE_VERSION.index}")
    end

    def bucket_path(key)
      hashed = hash_key(key)
      bucket_dir.join(*hash_to_segments(hashed))
    end

    def content_dir
      cache_path.join("content-v#{CACHE_VERSION.content}")
    end

    def content_path(integrity)
      sri = SSRI.parse(integrity, :single => true)
      cache_path.join(content_dir, sri.algorithm, *hash_to_segments(sri.hexdigest))
    end

    def hash_key(key)
      hash(key, "sha256")
    end

    def hash_entry(str)
      hash(str, "sha1")
    end

    def hash(str, digest)
      raise ArgumentError, "Cannot hash nil" if str.nil?
      raise NoSuchDigestError, "No digest implementation for #{digest}" unless impl = Digest(digest.upcase)
      impl.hexdigest(str)
    end

    def format_entry(entry)
      entry = Hash[entry.to_h.map {|k, v| [k.to_sym, v] }]
      return unless integrity = entry[:integrity]
      integrity = SSRI.parse(integrity)
      Info.new(
        entry[:key],
        integrity,
        content_path(integrity),
        entry[:time],
        entry[:size],
        entry[:metadata]
      )
    end
  end
end
