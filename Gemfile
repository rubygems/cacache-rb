# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in cacache-rb.gemspec
gemspec

gem "fixture_tree", :github => "segiddins/fixture_tree", :branch => "seg-pathname-write"

install_if RUBY_VERSION >= "2.0" do
  gem "rubocop", "~> 0.49.1"
end
