# frozen_string_literal: true

require "tmpdir"
require "fixture_tree"

RSpec.describe CACache::Cache do
  let(:fixture) { FixtureTree.create }
  let(:fixture_tree) { fixture.last }
  let(:cache_path) { fixture_tree.path }
  let(:ssri) { CACache::SSRI }

  after { FileUtils.rm_rf cache_path }

  subject(:cache) do
    described_class.new(cache_path).tap do |cache|
      cache.singleton_class.send(:public, *cache.private_methods(false))
    end
  end

  let(:empty_cache) do
    described_class.new("").tap do |cache|
      cache.singleton_class.send(:public, *cache.private_methods(false))
    end
  end

  def cache_content(entries = {})
    entries.reduce({}) do |acc, (k, content)|
      cpath = empty_cache.content_path(k)
      dir = acc
      cpath.dirname.descend {|v| dir = (dir[v.basename.to_s] ||= {}) }
      dir[cpath.basename.to_s] = content
      acc
    end
  end

  def cache_index(entries = {})
    entries.reduce({}) do |acc, (k, content)|
      cpath = empty_cache.bucket_path(k)
      dir = acc
      cpath.dirname.descend {|v| dir = (dir[v.basename.to_s] ||= {}) }
      dir[cpath.basename.to_s] =
        case content
        when String
          content
        when Hash, Array
          content = [content] if content.is_a?(Hash)
          content.map do |e|
            json = e.to_json
            e[:path] ||= cache.content_path(e[:integrity])
            "#{cache.hash_entry(json)}\t#{json}\n"
          end.join
        end
      acc
    end
  end

  describe "#read" do
    it "returns the cache content data" do
      content = "foobarbaz"
      integrity = ssri.from_data(content)
      fixture_tree.merge(cache_content(integrity => content))
      data = cache.read(integrity, {})
      expect(data).to eq content
    end
  end

  describe "#has_content" do
    it "returns { sri, size } when a cache file exists" do
      fixture_tree.merge(cache_content("sha1-deadbeef" => ""))

      content = cache.has_content("sha1-deadbeef")
      expect(content).to match(
        :sri => have_attributes(:to_s => "sha1-deadbeef"),
        :size => 0
      )

      content = cache.has_content("sha1-deadc000")
      expect(content).to be false
    end
  end

  let(:content) { "foobarbaz" }
  let(:integrity) { ssri.from_data(content) }
  let(:key) { "my-test-key" }
  let(:metadata) { { "foo" => "bar" } }
  let(:opts) { { :size => content.size, :metadata => metadata } }

  describe "#get" do
    it "gets data in bulk" do
      fixture_tree.merge(cache_content(integrity => content))
      cache.index_insert(key, integrity, opts)

      res = cache.get(key)
      expect(res).to eq(:data => content,
                        :integrity => integrity,
                        :metadata => metadata,
                        :size => content.size)

      res = cache.get_by_digest(integrity)
      expect(res).to eq content
    end

    it "raises ENOENT when not found" do
      expect { cache.get("my-test-key") }.to raise_error(Errno::ENOENT)
      expect(cache.get_info("my-test-key")).to be_nil
    end
  end

  describe "#get_info" do
    it "returns the index entry" do
      integrity = ssri.from_data(content)
      inserted_entry = cache.index_insert(key, integrity, opts)

      entry = cache.get_info(key)
      expect(entry.to_h).to eq inserted_entry.to_h
    end
  end

  describe "#put" do
    it "can insert an item by key" do
      inserted_integrity = cache.put(key, content)
      expect(inserted_integrity).to eq integrity

      data_path = cache.content_path(integrity)
      data = File.read(data_path)
      expect(data).to eq content
    end
  end

  describe "rm" do
    let(:key) { "my-test-key" }
    let(:content) { "foobarbaz" }
    let(:integrity) { CACache::SSRI.from_data(content) }
    let(:metadata) { { "foo" => "bar" } }

    describe "#rm_all" do
      it "deletes all content and index dirs" do
        fixture_tree.merge(cache_content(integrity => content))
        cache.index_insert(key, integrity, :metadata => metadata)
        cache_path.join("tmp").mkdir
        cache_path.join("other.rb").open("w") {|f| f << "hi" }

        expect(cache.rm_all).to be_nil

        expect(cache_path.children(false).map(&:to_s)).to match_array %w[other.rb tmp]
      end
    end

    describe "#rm_entry" do
      it "removes the entry and not the content" do
        fixture_tree.merge(cache_content(integrity => content))
        cache.index_insert(key, integrity, :metadata => metadata)

        cache.rm_entry(key)

        expect { cache.get(key) }.to raise_error(Errno::ENOENT, /no entry for #{key}/)
        expect(File.read(cache.content_path(integrity))).
          to eq(content), "content should remain in the cache"
      end
    end

    describe "#rm_content" do
      it "removes the content and not the index entry" do
        fixture_tree.merge(cache_content(integrity => content))
        cache.index_insert(key, integrity, :metadata => metadata)

        expect(cache.rm_content("sha512-bm8gY29udGVudA==")).to be false

        expect(cache.rm_content(integrity)).to be true
        expect { cache.get(key) }.to raise_error(Errno::ENOENT)
        content_path = cache.content_path(integrity)
        expect(content_path).not_to be_file
      end
    end
  end

  describe "#ls" do
    it "lists basic contents" do
      contents = {
        "whatever" => {
          :key => "whatever",
          :integrity => "sha512-deadbeef",
          :time => 12_345,
          :metadata => "omgsometa",
          :size => 234_234,
        },
        "whatnot" => {
          :key => "whatnot",
          :integrity => "sha512-bada55e5",
          :time => 54_321,
          :metadata => nil,
          :size => 425_345_345,
        },
      }
      fixture_tree.merge cache_index(contents)

      expect(cache.ls).to eq Hash[contents.map {|k, e| [k, cache.format_entry(e)] }]

      expect {|b| cache.ls(&b) }.to yield_successive_args(*contents.values.map {|e| cache.format_entry(e) })
    end

    it "handles separate keys in conflicting buckets" do
      contents = {
        "whatever" => {
          :key => "whatever",
          :integrity => "sha512-deadbeef",
          :time => 12_345,
          :metadata => "omgsometa",
          :size => 5,
        },
        "whatev" => {
          :key => "whatev",
          :integrity => "sha512-bada55e5",
          :time => 54_321,
          :metadata => nil,
          :size => 99_234_234,
        },
      }
      fixture_tree.merge cache_index("whatever" => contents.values)

      expect(cache.ls).to eq Hash[contents.map {|k, e| [k, cache.format_entry(e)] }]
    end

    it "works on an empty cache" do
      expect(cache.ls).to eq({})
    end

    it "ignores non-dir files" do
      index = cache_index(
        "whatever" => {
          :key => "whatever",
          :integrity => "sha512-deadbeef",
          :time => 12_345,
          :metadata => "omgsometa",
          :size => 234_234,
        }
      )
      index.each do |p, sd|
        sd["garbage"] = "hello world #{p}" if sd.is_a?(Hash)
      end
      index["garbage"] = "hello world"

      fixture_tree.merge(index)

      ls = cache.ls
      expect(ls.size).to eq 1
      expect(ls["whatever"]).to have_attributes(:key => "whatever")
    end
  end

  describe "#verify" do
    let(:key) { "my-test-key" }
    let(:content) { "foobarbaz" }
    let(:integrity) { CACache::SSRI.from_data(content) }
    let(:metadata) { { "foo" => "bar" } }
    let(:bucket) { cache.bucket_path(key) }
    let(:log) { [] }
    let(:opts) { { :log => proc {|msg| log << msg } } }

    def mock_cache
      fixture_tree.merge(cache_content(integrity => content))
      FileUtils.mkdir_p(cache_path.join("tmp"))
      cache.index_insert(key, integrity, :size => content.size, :metadata => metadata)
    end

    it "removes corrupted index entries from buckets" do
      mock_cache

      bucket_data = File.read(bucket)
      File.open(bucket, "a") {|f| f << "\n234uhhh" }

      stats = cache.verify(opts)

      expect(stats.without_times.to_s).to eq <<-EOS.strip
CACache::VerificationStats
---
bad_content_count: 0
kept_size: 9
missing_content: 0
reclaimed_count: 0
reclaimed_size: 0
rejected_entries: 0
total_entries: 1
verified_content: 1
      EOS

      new_bucket_data = File.read(bucket)

      bucket_entry = JSON.parse(new_bucket_data.split("\t")[1])
      target_entry = JSON.parse(bucket_data.split("\t")[1])

      target_entry["time"] = bucket_entry["time"]

      expect(bucket_entry).to eq(target_entry), "bucket only contains good entry"
    end

    it "removes shadowed index entries from buckets" do
      mock_cache
      new_entry = cache.index_insert(key, integrity, :size => 109, :metadata => "meh")

      expect(cache.verify.without_times.to_s).to eq <<-EOS.strip
CACache::VerificationStats
---
bad_content_count: 0
kept_size: 9
missing_content: 0
reclaimed_count: 0
reclaimed_size: 0
rejected_entries: 0
total_entries: 1
verified_content: 1
      EOS

      bucket_data = bucket.read
      entry_json = JSON.dump(:key => new_entry.key,
                             :integrity => new_entry.integrity.to_s,
                             :time => bucket_data.match(/"time":(\d+)/)[1].to_i,
                             :size => content.size,
                             :metadata => new_entry.metadata)
      expect(bucket_data).to eq "#{cache.hash_entry(entry_json)}\t#{entry_json}\n"
    end

    it "accepts a function for filtering of index entries" do
      key2 = key + "aaa"
      key3 = key + "bbb"
      mock_cache
      new_entries = {
        key2 => cache.index_insert(key2, integrity, :size => content.size, :metadata => "hi"),
        key3 => cache.index_insert(key3, integrity, :size => content.size, :metadata => "hi again"),
      }
      stats = cache.verify(:filter => proc {|entry| entry.key.length == key2.length })

      expect(stats.without_times.to_s).to eq <<-EOS.strip
CACache::VerificationStats
---
bad_content_count: 0
kept_size: #{content.size}
missing_content: 0
reclaimed_count: 0
reclaimed_size: 0
rejected_entries: 1
total_entries: 2
verified_content: 1
      EOS

      entries = cache.ls
      entries[key2].time = new_entries[key2].time
      entries[key3].time = new_entries[key3].time
      expect(new_entries).to eq entries
    end

    it "removes corrupted content" do
      content_path = cache.content_path(integrity)
      mock_cache
      content_path.open("w") {|f| f << content[0..-2] }

      stats = cache.verify
      expect(content_path).not_to be_file
      expect(stats.without_times.to_s).to eq <<-EOS.strip
CACache::VerificationStats
---
bad_content_count: 1
kept_size: 0
missing_content: 1
reclaimed_count: 1
reclaimed_size: #{content.size - 1}
rejected_entries: 1
total_entries: 0
verified_content: 0
      EOS
    end

    it "removes content not referenced by any entries" do
      fixture_tree.merge(cache_content(integrity => content))

      expect(cache.verify.without_times.to_s).to eq <<-EOS.strip
CACache::VerificationStats
---
bad_content_count: 0
kept_size: 0
missing_content: 0
reclaimed_count: 1
reclaimed_size: #{content.size}
rejected_entries: 0
total_entries: 0
verified_content: 0
      EOS

      expect(cache.content_path(integrity)).not_to be_file
    end

    it "cleans up the contents of the tmp dir" do
      tmp_file = cache_path.join("tmp", "x")
      misc_file = cache_path.join("y")

      mock_cache

      tmp_file.parent.mkpath
      tmp_file.open("w") {|f| f << "" }
      misc_file.open("w") {|f| f << "" }

      cache.verify

      expect { tmp_file.stat }.to raise_error(Errno::ENOENT)
      expect(misc_file.stat).not_to be_nil
    end

    it "writes a file with the last verification time" do
      expect(cache.verify_last_run).to be_nil

      cache.verify

      from_last_run = cache.verify_last_run
      data = cache_path.join("_lastverified").open("r:utf-8", &:read)
      from_file = Time.at(data.to_i)
      expect(from_last_run).to eq(from_file)
    end
  end
end
