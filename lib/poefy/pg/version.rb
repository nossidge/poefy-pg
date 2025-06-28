#!/usr/bin/env ruby
# Encoding: UTF-8

module Poefy

  module Pg

    def self.version_number
      major = 2
      minor = 0
      tiny  = 0
      pre   = nil

      string = [major, minor, tiny, pre].compact.join('.')
      Gem::Version.new string
    end

    def self.version_date
      '2025-06-28'
    end

  end

end
