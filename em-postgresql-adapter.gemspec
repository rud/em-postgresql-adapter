Gem::Specification.new do |s|
  s.name     = "em-postgresql-adapter"
  s.version  = "0.1"
  s.date     = "2011-04-23"
  s.summary  = "PostgreSQL fiber-based ActiveRecord connection adapter for Ruby 1.9"
  s.email    = "ruben@leftbee.net"
  s.homepage = "http://github.com/leftbee/em-postgresql-adapter"
  s.authors  = ["Ruben Nine"]
  # s.files    = Dir['Rakefile', '{bin,lib,man,test,spec}/**/*', 'README*', 'LICENSE*'] & `git ls-files -z`.split("\0")
  s.files    = [
    "em-postgresql-adapter.gemspec",
    "lib/active_record/connection_adapters/em_postgresql_adapter.rb",
    "lib/em-postgresql-adapter/fibered_postgresql_connection.rb"
  ] + Dir['Rakefile',
    'README*',
    'LICENSE*',
    'lib/em-postgresql-adapter/connection_pool/**/*'] & `git ls-files -z`.split("\0")
  s.add_dependency('pg', '>= 0.8.0')
end
