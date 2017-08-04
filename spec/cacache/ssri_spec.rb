# frozen_string_literal: true

RSpec.describe CACache::SSRI do
  let(:test_data) { File.read(__FILE__) }

  def hash(data, algo)
    Digest(algo.upcase).base64digest(data)
  end

  describe ".check" do
    let(:sri) { described_class.parse "sha512-#{hash(test_data, :sha512)}" }
    let(:meta) { sri["sha512"].first }

    it "verifies" do
      expect(described_class.check(test_data, sri)).to eq meta
      expect(described_class.check(test_data, sri.to_s)).to eq meta
    end

    it "verifies if any of the hases under the choser algorithm match" do
      expect(described_class.check(test_data, "sha512-nope #{sri} sha512-nopeagain")).to eq meta
    end

    it "returns false when verification fails" do
      expect(described_class.check("nope", sri)).to be false
    end

    it "returns false on invalid sri input" do
      expect(described_class.check("nope", "sha512-nope")).to be false
    end

    it "returns false on garbage" do
      expect(described_class.check("nope", "garbage")).to be false
    end

    it "returns false on an empty sri string" do
      expect(described_class.check("nope", "")).to be false
    end
  end

  describe "from" do
    describe "#from_hex" do
      it "creates an Integrity" do
        expect(described_class.from_hex("deadbeef", "sha1").to_s).to eq "sha1-3q2+7w=="
      end

      it "adds options the the entry" do
        expect(described_class.from_hex("deadbeef", "sha1", :options => %w[a b c]).to_s).to eq "sha1-3q2+7w==?a?b?c"
      end
    end

    describe "#from_data" do
      it "creates an Integrity" do
        expect(described_class.from_data(test_data).to_s).
          to eq "sha512-#{hash(test_data, :sha512)}"
      end

      it "creates an Integrity with multiple algorithms" do
        expect(described_class.from_data(test_data, :algorithms => %w[sha256 sha384]).to_s).
          to eq "sha256-#{hash(test_data, :sha256)} sha384-#{hash(test_data, :sha384)}"
      end

      it "creates an Integrity with options" do
        expect(described_class.from_data(test_data, :algorithms => %w[sha256 sha384], :options => %w[foo bar]).to_s).
          to eq "sha256-#{hash(test_data, :sha256)}?foo?bar sha384-#{hash(test_data, :sha384)}?foo?bar"
      end
    end
  end

  describe described_class::Integrity do
    describe "#to_s" do
      subject(:sri) { CACache::SSRI.parse("sha512-foo sha256-bar!") }

      it { is_expected.to have_attributes :to_s => "sha512-foo sha256-bar!" }

      it "accepts accepts the strict mode option" do
        expect(sri.to_s(:strict => true)).to eq "sha512-foo"
      end

      it "accepts accepts the separator option" do
        expect(sri.to_s(:separator => "\n")).to eq "sha512-foo\nsha256-bar!"
      end
    end

    describe "#pick_algorithm" do
      subject(:sri) { CACache::SSRI.parse("sha1-foo sha512-bar sha384-baz") }

      it "picks the best algorithm" do
        expect(sri.pick_algorithm).to eq "sha512"
      end

      it "picks an algorithm when all are unknown" do
        sri = CACache::SSRI.parse("unknown-deadbeef uncertain-bada55")
        expect(sri.pick_algorithm).to eq "unknown"
      end

      it "uses the custom method to pick" do
        expect(sri.pick_algorithm(:pick_algorithm => proc {|a| -a.size })).
          to eq "sha1"
      end

      it "raises when there are no algorithms" do
        sri = CACache::SSRI.parse("")
        expect { sri.pick_algorithm }.
          to raise_error ArgumentError, /No algorithms available/
      end
    end

    describe "#hexdigest" do
      it "returns the hex version of the base64 digest" do
        expect(CACache::SSRI.parse("sha512-foo0").hexdigest).
          to eq "7e8a34"
        expect(CACache::SSRI.parse("sha512-bar3", :single => true).hexdigest).
          to eq "6daaf7"
      end
    end
  end

  describe ".parse" do
    def parse(*args)
      CACache::SSRI.parse(*args)
    end
    let(:sha) { hash(test_data, :sha512) }

    it "parses a single entry integrity string" do
      expect(parse("sha512-#{sha}").to_h).to eq(
        "sha512" => [CACache::SSRI::Hash.new("sha512-#{sha}", "sha512", sha, [])]
      )
    end

    it "parses a single entry integrity string directly to a hash" do
      expect(parse("sha512-#{sha}", :single => true)).to eq(
        CACache::SSRI::Hash.new("sha512-#{sha}", "sha512", sha, [])
      )
    end

    it "parses a single entry Integrity" do
      integrity = parse("sha512-#{sha}")
      expect(parse(integrity)).to eq integrity
    end

    it "parses a Hash" do
      h = parse("sha512-#{sha}", :single => true)
      expect(parse(h)).to eq parse("sha512-#{sha}")
    end

    it "parses multi-entry strings" do
      hashes = %W[
        sha1-#{hash(test_data, :sha1)}
        sha256-#{hash(test_data, :sha256)}
        sha1-OthERhaSh
        unknown-OOOO0000OOOO
      ]
      expect(parse(hashes.join(" ")).to_h).to eq(
        "sha1" => [
          CACache::SSRI::Hash.new(hashes[0], "sha1", hash(test_data, :sha1), []),
          CACache::SSRI::Hash.new(hashes[2], "sha1", "OthERhaSh", []),
        ],
        "sha256" => [
          CACache::SSRI::Hash.new(hashes[1], "sha256", hash(test_data, :sha256), []),
        ],
        "unknown" => [

          CACache::SSRI::Hash.new(hashes[3], "unknown", "OOOO0000OOOO", []),
        ]
      )
    end

    it "parses any whitespace as entry separators" do
      integrity = "\tsha512-foobarbaz \n\rsha384-bazbarfoo\n         \t  \t\t\r\n \b sha256-foo"
      expect(parse(integrity).to_h).to eq(
        "sha512" => [
          CACache::SSRI::Hash.new("sha512-foobarbaz", "sha512", "foobarbaz", []),
        ],
        "sha384" => [
          CACache::SSRI::Hash.new("sha384-bazbarfoo", "sha384", "bazbarfoo", []),
        ],
        "sha256" => [
          CACache::SSRI::Hash.new("sha256-foo", "sha256", "foo", []),
        ]
      )
    end

    it "discards invalid entries" do
      invalid = %w[thisisbad -deadbeef sha512- -]
      valid = "sha512-#{sha}"
      expect(parse(invalid.+([valid]).join(" ")).to_h).to eq(
        "sha512" => [
          CACache::SSRI::Hash.new(valid, "sha512", sha, []),
        ]
      )
    end

    it "strips whitespace" do
      sri = "         \t sha512-#{sha} \r\n "
      expect(parse(sri).to_h).to eq(
        "sha512" => [
          CACache::SSRI::Hash.new(sri.strip, "sha512", sha, []),
        ]
      )
    end

    it "supports strict parsing" do
      valid = "sha512-#{sha}"
      bad_algorithm = "sha1-#{hash(test_data, :sha1)}"
      bad_base64 = "sha512-@\#$@%\#$"
      bad_opts = "#{valid}?\x01\x02"

      expect(parse([bad_algorithm, bad_base64, bad_opts, valid].join(" "), :strict => true).to_s).
        to eq valid
    end
  end
end
