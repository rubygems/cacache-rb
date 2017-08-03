
# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "cacache/version"

Gem::Specification.new do |spec|
  spec.name          = "cacache-rb"
  spec.version       = CACache::VERSION
  spec.authors       = ["Samuel Giddins"]
  spec.email         = ["segiddins@segiddins.me"]

  spec.summary       = "A content-addressable file system cache"
  spec.homepage      = "https://github.com/segiddins/cacache-rb"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 1.8.7"

  spec.add_development_dependency "bundler", ">= 1.15.3", "< 3"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "rspec", "~> 3.6"
  spec.add_development_dependency "rubocop", "~> 0.49.1"
  spec.add_development_dependency "fixture_tree", "~> 1.0.0"
end
