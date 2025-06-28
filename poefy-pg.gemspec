# Encoding: UTF-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'poefy/pg/version.rb'

Gem::Specification.new do |s|
  s.name          = 'poefy-pg'
  s.authors       = ['Paul Thompson']
  s.email         = ['nossidge@gmail.com']

  s.summary       = %q{PostgreSQL interface for the 'poefy' gem}
  s.description   = %q{PostgreSQL interface for the 'poefy' gem}
  s.homepage      = 'https://github.com/nossidge/poefy-pg'

  s.version       = Poefy::Pg.version_number
  s.date          = Poefy::Pg.version_date
  s.license       = 'GPL-3.0-or-later'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ['lib']

  s.required_ruby_version = '>= 3.2.0'

  s.add_development_dependency('bundler',     '~> 2.6')
  s.add_development_dependency('rake',        '~> 10.0')
  s.add_development_dependency('rspec',       '~> 3.0')
  s.add_development_dependency('ruby_rhymes', '~> 0.1')

  s.add_runtime_dependency('poefy', '~> 2.0', '>= 2.0.1')
  s.add_runtime_dependency('pg',    '~> 1.5', '>= 1.5.9')
end
