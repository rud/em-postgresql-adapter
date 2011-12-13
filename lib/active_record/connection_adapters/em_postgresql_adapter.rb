require 'em-synchrony/activerecord'
require 'active_record/connection_adapters/abstract_adapter'
require 'active_record/connection_adapters/postgresql_adapter'
require 'em-postgresql-adapter/fibered_postgresql_connection'

if ActiveRecord::VERSION::STRING < "3.1"
  raise "This version of em-postgresql-adapter requires ActiveRecord >= 3.1"
end

module ActiveRecord
  module ConnectionAdapters
    class EMPostgreSQLAdapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
      class Client < ::EM::DB::FiberedPostgresConnection
        include EM::Synchrony::ActiveRecord::Client
      end

      class ConnectionPool < EM::Synchrony::ConnectionPool
        # via method_missing async_exec will be recognized as async method
        def async_exec(*args, &blk)
          execute(false) do |conn|
            conn.send(:async_exec, *args, &blk)
          end
        end
      end

      include EM::Synchrony::ActiveRecord::Adapter

      def connect
        @connection
      end
    end
  end # ConnectionAdapters

  class Base
    DEFAULT_POOL_SIZE = 5

    # Establishes a connection to the database that's used by all Active Record objects
    def self.em_postgresql_connection(config) # :nodoc:
      config = config.symbolize_keys
      host     = config[:host]
      port     = config[:port] || 5432
      username = config[:username].to_s
      password = config[:password].to_s
      poolsize = config[:pool] || DEFAULT_POOL_SIZE

      if config.has_key?(:database)
        database = config[:database]
      else
        raise ArgumentError, "No database specified. Missing argument: database."
      end
      adapter = ActiveRecord::ConnectionAdapters::EMPostgreSQLAdapter
      options = [host, port, nil, nil, database, username, password]

      client = adapter::ConnectionPool.new(size: poolsize) do
        adapter::Client.connect(*options)
      end 
      adapter.new(client, logger, options, config)
    end
  end

end # ActiveRecord
