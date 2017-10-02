require 'bundler/setup'
Bundler.setup

require 'tempfile'
require 'poefy'

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

RSpec.configure do |config|
  # some (optional) config here
end
