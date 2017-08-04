# frozen_string_literal: true

module CACache
  module Util
  module_function

    def uniq_slug(uniq)
      return Random::DEFAULT.bytes(4).unpack("H*").first unless uniq
      Digest(:MD5).hexdigest(uniq)[-8..-1]
    end

    def unique_filename(path, prefix, uniq = nil)
      path.join(path, prefix ? prefix + "-" : "", uniq_slug(uniq))
    end

    def fix_owner(filepath, uid, gid)
      return if !uid && !gid
      return unless Process.uid
      return if uid == Process.uid && gid == Process.gid
      begin
        File.chown(uid, gid, filepath)
      rescue Errno::ENOENT
        nil
      end
    end

    def fix_owner_mkdir_fix(p, uid, gid)
      FileUtils.mkdir_p(p)
      fix_owner(p, uid, gid)
    rescue Errno::EEXIST
      fix_owner(p, uid, gid)
    end

    def hash_to_segments(hash)
      [
        hash[0, 2],
        hash[2, 2],
        hash[4..-1],
      ]
    end

    def move_file(src, dest)
      begin
        File.link(src, dest)
      rescue Errno::EEXIST, Errno::EBUSY
        nil
      rescue Errno::EPERM
        raise unless Gem.win_platform?
      end

      File.unlink(src)
      File.chmod(0o444, dest) unless Gem.win_platform?
    end

    def mktmp(cache_dir, opts = {})
      tmp_target = unique_filename(cache_dir.join("tmp"), opts[:tmp_prefix])
      fix_owner_mkdir_fix(tmp_target.dirname, opts[:uid], opts[:gid])
      return tmp_target unless block_given?
      begin
        yield tmp_target
      ensure
        FileUtils.rm_rf(tmp_target)
      end
    end

    def fix_tmpdir(cache_dir, opts)
      fix_owner(cache_dir.join("tmp"), opts[:uid], opts[:gid])
    end

    def recurse_children(dir, depth = -1, &blk)
      dir.each_child do |child|
        if depth <= 0 || !child.directory?
          yield child
        else
          recurse_children(child, depth - 1, &blk)
        end
      end
    rescue Errno::ENOENT, Errno::ENOTDIR
      nil
    end
  end
end
