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

    def rm_entry(key, opts = {})
      index_insert(key, nil, opts)
    end

    def rm_content(integrity)
      return false unless content = has_content(integrity)
      return false unless sri = content[:sri]
      FileUtils.rm_rf content_path(sri)
      true
    end

    # Integrity

    def verify_mark_start_time(opts)
      { :start_time => Time.now }
    end
    private :verify_mark_start_time

    def verify_fix_permissions(opts)
      opts[:log].call("fixing cache permissions")
      fix_owner_mkdir_fix(cache_path, opts[:uid], opts[:gid])
      fix_owner(cache_path, opts[:uid], opts[:gid])
      nil
    end
    private :verify_fix_permissions

    def verify_content(path, sri)
      stat = path.stat
      valid = begin
        SSRI.check!(path, sri)
        true
      rescue IntegrityError
        FileUtils.rm_rf path
        false
      end
      {
        :size => stat.size,
        :valid => valid,
      }
    rescue Errno::ENOENT
      {
        :size => 0,
        :valid => false,
      }
    end
    private :verify_content

    def verify_garbage_collect(opts)
      opts[:log].call("garbage-collecting content")
      filter = opts[:filter]
      live_content = Set.new
      ls do |entry|
        next if filter && !filter.call(entry)
        live_content << entry.integrity.to_s
      end
      stats = {
        :verified_content => 0,
        :reclaimed_count => 0,
        :reclaimed_size => 0,
        :bad_content_count => 0,
        :kept_size => 0,
      }
      Pathname.glob(content_dir.join("**/*")).each do |f|
        next if f.directory?
        split = f.to_s.split File::SEPARATOR
        digest = split[-3, 3].join
        algo = split[-4]
        integrity = SSRI.from_hex(digest, algo)
        if live_content.include?(integrity.to_s)
          info = verify_content(f, integrity)
          if !info[:valid]
            stats[:reclaimed_count] += 1
            stats[:bad_content_count] += 1
            stats[:reclaimed_size] += info[:size]
          else
            stats[:verified_content] += 1
            stats[:kept_size] += info[:size]
          end
        else
          stats[:reclaimed_count] += 1
          size = f.size
          FileUtils.rm_rf f
          stats[:reclaimed_size] += size
        end
      end
      stats
    end
    private :verify_garbage_collect

    # @private
    class RebuildIndexBucket
      attr_reader :entries, :path
      def initialize(path)
        @entries = []
        @path = path
      end
    end
    private_constant :RebuildIndexBucket if respond_to?(:private_constant)

    def verify_rebuild_bucket(bucket, stats, opts)
      File.truncate(bucket.path, 0)
      bucket.entries.each do |entry|
        begin
          content = content_path(entry.integrity)
          size = content.stat.size
          index_insert(entry.key, entry.integrity, opts.merge(:size => size, :metadata => entry.metadata))
          stats[:total_entries] += 1
        rescue Errno::ENOENT
          stats[:rejected_entries] += 1
          stats[:missing_content] += 1
        end
      end
    end
    private :verify_rebuild_bucket

    def verify_rebuild_index(opts)
      opts[:log].call("rebuilding index")
      entries = ls
      stats = { :missing_content => 0, :rejected_entries => 0, :total_entries => 0 }
      buckets = {}
      entries.each do |k, entry|
        hashed = hash_key(k)
        excluded = opts[:filter] && !opts[:filter].call(entry)
        stats[:rejected_entries] += 1 if excluded
        if !excluded && buckets[hashed]
          buckets[hashed].entries << entry
        elsif excluded && buckets[hashed]
          nil
        else
          bucket = buckets[hashed] = RebuildIndexBucket.new(bucket_path(k))
          bucket.entries << entry unless excluded
        end
      end
      buckets.each do |_key, bucket|
        verify_rebuild_bucket(bucket, stats, opts)
      end
      stats
    end
    private :verify_rebuild_index

    def verify_clean_tmp(opts)
      opts[:log].call("cleaning tmp directory")
      FileUtils.rm_rf cache_path.join("tmp")
      nil
    end
    private :verify_clean_tmp

    def verify_write_verifile(opts)
      verifile = cache_path.join("_lastverified")
      opts[:log].call("writing verifile to #{verifile}")
      verifile.open("w") {|f| f << Time.now.to_i.to_s }
      nil
    end
    private :verify_write_verifile

    def verify_mark_end_time(opts)
      { :end_time => Time.now }
    end
    private :verify_mark_end_time

    def verify(opts = {})
      log = opts[:log] ||= proc {}
      log.call("verifying cache at #{cache_path}")
      [
        proc { verify_mark_start_time(opts) },
        proc { verify_fix_permissions(opts) },
        proc { verify_garbage_collect(opts) },
        proc { verify_rebuild_index(opts) },
        proc { verify_clean_tmp(opts) },
        proc { verify_write_verifile(opts) },
        proc { verify_mark_end_time(opts) },
      ].each_with_index.reduce(VerificationStats.new) do |stats, (step, i)|
        label = "step #{i}"
        start = Time.new

        if s = step.call(opts)
          s.each {|k, v| stats[k] = v }
        end
        end_time = Time.new

        stats.run_time ||= {}
        stats.run_time[label] = end_time - start

        stats
      end.tap do |stats|
        stats.run_time[:total] = stats.end_time - stats.start_time
        log.call("verification finished for #{cache_path} in #{stats.run_time[:total]}ms")
      end
    end

    def verify_last_run
      verifile = cache_path.join("_lastverified")
      return unless verifile.file?
      data = verifile.read(:encoding => "utf-8")
      Time.at(data.to_i)
    end

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
