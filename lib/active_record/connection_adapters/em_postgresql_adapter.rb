require 'active_record/connection_adapters/postgresql_adapter'
require 'em-postgresql-adapter/fibered_postgresql_connection'

module ActiveRecord
  module ConnectionAdapters

    def self.fiber_pools
      @fiber_pools ||= []
    end
    def self.register_fiber_pool(fp)
      fiber_pools << fp
    end

    class FiberedMonitor
      class Queue
        def initialize
          @queue = []
        end

        def wait(timeout)
          t = timeout || 5
          fiber = Fiber.current
          x = EM::Timer.new(t) do
            @queue.delete(fiber)
            fiber.resume(false)
          end
          @queue << fiber
          Fiber.yield.tap do
            x.cancel
          end
        end

        def signal
          fiber = @queue.pop
          fiber.resume(true) if fiber
        end
      end

      def synchronize
        yield
      end

      def new_cond
        Queue.new
      end
    end

    # ActiveRecord's connection pool is based on threads.  Since we are working
    # with EM and a single thread, multiple fiber design, we need to provide
    # our own connection pool that keys off of Fiber.current so that different
    # fibers running in the same thread don't try to use the same connection.
    class ConnectionPool
      def initialize(spec)
        @spec = spec

        # The cache of reserved connections mapped to threads
        @reserved_connections = {}

        # The mutex used to synchronize pool access
        @connection_mutex = FiberedMonitor.new
        @queue = @connection_mutex.new_cond

        # default 5 second timeout unless on ruby 1.9
        @timeout = spec.config[:wait_timeout] || 5

        # default max pool size to 5
        @size = (spec.config[:pool] && spec.config[:pool].to_i) || 5

        @connections = []
        @checked_out = []
      end

      def clear_stale_cached_connections!

        # If we aren't using any fiber pools, then don't run this code otherwise it
        # will checkin *all* connections and clear the @reserved_connections hash.
        return if ActiveRecord::ConnectionAdapters.fiber_pools.empty?
        
        cache = @reserved_connections
        keys = Set.new(cache.keys)

        ActiveRecord::ConnectionAdapters.fiber_pools.each do |pool|
          pool.busy_fibers.each_pair do |object_id, fiber|
            keys.delete(object_id)
          end
        end

        keys.each do |key|
          next unless cache.has_key?(key)
          checkin cache[key]
          cache.delete(key)
        end
      end

      private

      def current_connection_id #:nodoc:
        Fiber.current.object_id
      end

      # The next three methods (#checkout_new_connection, #checkout_existing_connection and #checkout_and_verify) require modification.
      # The reason is because @connection_mutex.synchronize was modified to do nothing, which means #checkout is unguarded.  It was
      # assumed that was ok because the current fiber wouldn't yield during execution of #checkout, but that is untrue.  Both #new_connection
      # and #checkout_and_verify will yield the current fiber, thus allowing the body of #checkout to be accessed by multiple fibers at once.
      # So if we want this to work without a lock, we need to make sure that the variables used to test the conditions in #checkout are
      # modified *before* the current fiber is yielded and the next fiber enters #checkout.

      def checkout_new_connection

        # #new_connection will yield the current fiber, thus we need to fill @connections and @checked_out with placeholders so
        # that the next fiber to enter #checkout will take the appropriate action.  Once we actually have our connection, we
        # replace the placeholders with it.

        @connections << current_connection_id
        @checked_out << current_connection_id

        c = new_connection

        @connections[@connections.index(current_connection_id)] = c
        @checked_out[@checked_out.index(current_connection_id)] = c

        checkout_and_verify(c)
      end

      def checkout_existing_connection
        c = (@connections - @checked_out).first
        @checked_out << c
        checkout_and_verify(c)
      end      

      def checkout_and_verify(c)
        c.run_callbacks :checkout
        c.verify!
        c
      end

    end # ConnectionPool

    class EMPostgreSQLAdapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
      # Returns 'FiberedPostgreSQL' as adapter name for identification purposes.
      def adapter_name
        'EMPostgreSQL'
      end

      def connect
        @connection = ::EM::DB::FiberedPostgresConnection.connect(*@connection_parameters[1..(@connection_parameters.length-1)])
      end

      # Close then reopen the connection.
      def reconnect!
        disconnect!
        connect
      end
    end

  end # ConnectionAdapters

  class Base
    # Establishes a connection to the database that's used by all Active Record objects
    def self.em_postgresql_connection(config) # :nodoc:
      config = config.symbolize_keys
      host     = config[:host]
      port     = config[:port] || 5432
      username = config[:username].to_s
      password = config[:password].to_s
      size     = config[:connections] || 4

      if config.has_key?(:database)
        database = config[:database]
      else
        raise ArgumentError, "No database specified. Missing argument: database."
      end

      # The postgres drivers don't allow the creation of an unconnected PGconn object,
      # so just pass a nil connection object for the time being.
      ::ActiveRecord::ConnectionAdapters::EMPostgreSQLAdapter.new(nil, logger, [size, host, port, nil, nil, database, username, password], config)
    end
  end

end # ActiveRecord
