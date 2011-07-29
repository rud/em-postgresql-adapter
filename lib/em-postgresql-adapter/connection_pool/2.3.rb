# ActiveRecord 2.3 specific implemenation for ConnectionPool.

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
  end
end
