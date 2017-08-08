# CACache

`CACache` is a Ruby implementation of a content-addressable cache, compatible with NPM's [cacache](https://github.com/zkat/cacache) package. It's fast, capable of concurrent use, and will never yield corrupted data, even if cache files get corrupted or manipulated.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cacache-rb'
```

And then execute:

```sh
bundle
```

Or install it yourself as:

```sh
gem install cacache-rb
```

## Usage

Simply initialize a `CACache::Cache` object with a `cache_path`. That cache object implements all of the methods required to use the cache. See the [API docs](http://www.rubydoc.info/gems/cacache) for complete documentation of all available functionality.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/rrake` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/segiddins/cacache-rb>. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Cacache::Rb project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/segiddins/cacache-rb/blob/master/CODE_OF_CONDUCT.md).
