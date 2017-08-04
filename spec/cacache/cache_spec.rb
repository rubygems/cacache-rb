# frozen_string_literal: true

require "tmpdir"
require "fixture_tree"

RSpec.describe CACache::Cache do
  let(:fixture) { FixtureTree.create }
  let(:fixture_tree) { fixture.last }
  let(:cache_path) { fixture_tree.path }
  let(:ssri) { CACache::SSRI }

  after { FileUtils.rm_rf cache_path }

  subject(:cache) { described_class.new(cache_path) }

  def cache_content(entries = {})
    entries.reduce({}) do |acc, (k, content)|
      cpath = described_class.new("").send(:content_path, k)
      dir = acc
      cpath.dirname.descend {|v| dir = (dir[v.basename.to_s] ||= {}) }
      dir[cpath.basename.to_s] = content
      acc
    end
  end

  def cache_index(entries = {})
    cache = described_class.new("")
    entries.reduce({}) do |acc, (k, content)|
      cpath = cache.send(:bucket_path, k)
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
            e[:path] ||= cache.send(:content_path, e[:integrity])
            "#{cache.send(:hash_entry, json)}\t#{json}\n"
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
      data = cache.send(:read, integrity, {})
      expect(data).to eq content
    end
  end

  describe "#has_content" do
    it "returns { sri, size } when a cache file exists" do
      fixture_tree.merge(cache_content("sha1-deadbeef" => ""))

      content = cache.send(:has_content, "sha1-deadbeef")
      expect(content).to match(
        :sri => have_attributes(:to_s => "sha1-deadbeef"),
        :size => 0
      )

      content = cache.send(:has_content, "sha1-deadc000")
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
      cache.send(:index_insert, key, integrity, opts)

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
      inserted_entry = cache.send(:index_insert, key, integrity, opts)

      entry = cache.get_info(key)
      expect(entry.to_h).to eq inserted_entry.to_h
    end
  end

  describe "#put" do
    it "can insert an item by key" do
      inserted_integrity = cache.put(key, content)
      expect(inserted_integrity).to eq integrity

      data_path = cache.send(:content_path, integrity)
      data = File.read(data_path)
      expect(data).to eq content
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

      expect(cache.ls).to eq Hash[contents.map {|k, e| [k, cache.send(:format_entry, e)] }]

      expect {|b| cache.ls(&b) }.to yield_successive_args(*contents.values.map {|e| cache.send(:format_entry, e) })
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

      expect(cache.ls).to eq Hash[contents.map {|k, e| [k, cache.send(:format_entry, e)] }]
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
end
