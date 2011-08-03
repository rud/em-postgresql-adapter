# ActiveRecord 3.0 specific implemenation for ConnectionPool. This is cut-and-pasted from the original
# implementation from https://github.com/bruchu/em-postgresql-adapter/tree/c7aae3cbea75a35501ef8b466a4c53dbb52900d4
# in lib/active_record/connection_adapters/em_postgres_adapter.rb
module ActiveRecord
  module ConnectionAdapters

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

      def checkout_and_verify(c)
        @checked_out << c
        c.run_callbacks :checkout
        c.verify!
        c
      end
    end # ConnectionPool
  end
end
