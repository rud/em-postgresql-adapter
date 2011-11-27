require 'fiber'
require 'eventmachine'
require 'pg'

module EM
  module DB
    # Patching our PGConn-based class to wrap async_exec (alias for async_query) calls into Ruby Fibers
    # ActiveRecord 3.1 calls PGConn#async_exec and also PGConn#send_query_prepared (the latter hasn't been patched here yet -- see below)
    class FiberedPostgresConnection < PGconn

      module Watcher
        def initialize(client, deferable)
          @client = client
          @deferable = deferable
        end

        def notify_readable
          begin
            detach

            @client.consume_input while @client.is_busy

            res, data = 0, []
            while res != nil
              res = @client.get_result
              data << res unless res.nil?
            end

            @deferable.succeed(data.last)
          rescue Exception => e
            @deferable.fail(e)
          end
        end
      end

      def async_exec(sql)
        if ::EM.reactor_running?
          send_query sql
          deferrable = ::EM::DefaultDeferrable.new
          ::EM.watch(self.socket, Watcher, self, deferrable).notify_readable = true
          fiber = Fiber.current
          deferrable.callback do |result|
            fiber.resume(result)
          end
          deferrable.errback do |err|
            fiber.resume(err)
          end
          Fiber.yield.tap do |result|
            raise result if result.is_a?(Exception)
          end
        else
          super(sql)
        end
      end
      alias_method :async_query, :async_exec

      # TODO: Figure out whether patching PGConn#send_query_prepared will have a noticeable effect and implement accordingly
      # NOTE: ActiveRecord 3.1 calls PGConn#send_query_prepared from ActiveRecord::ConnectionAdapters::PostgreSQLAdapter#exec_cache.
      # def send_query_prepared(statement_name, *params)
      # end

    end #FiberedPostgresConnection
  end #DB
end #EM
