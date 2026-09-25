# frozen_string_literal: true

require "rack/body_proxy"

module Langsys
  module Rails
    # Rack middleware marking the request boundary for the base SDK. The Railtie inserts it in
    # front of ActionDispatch::Executor.
    #
    # The base SDK's client is process-wide and outlives every request a Puma or Falcon worker
    # serves, so two of its obligations need a host lifecycle hook — and its CONFORMANCE.md
    # names this wrapper as the owner of both:
    #
    # * GATE-3: the write decision must not survive one request. It is dropped as the request
    #   enters, and again once the request is done.
    # * REG-3 / SRV-3: discovered phrases are flushed before the request's context ends, and
    #   only after the response has been sent. Registration is not the visitor's work, so it
    #   never spends their wait. The request runs inside a core request scope, so a miss it
    #   records is held from every flush — including another request's — until its own
    #   response is out. The scope needs no client, so it is open even for the request that
    #   builds the client.
    #
    # Both calls are the base SDK's own. Whether this session may write, what is sent, what is
    # kept and what is logged are decided there (BIND-2); this class adapts timing only (BIND-1).
    #
    # "After the response has been sent" follows ActionDispatch::Executor exactly. A server that
    # provides +rack.response_finished+ runs those callables once the response is processed, in
    # reverse order of registration; otherwise the server closes the body after writing it.
    # Sitting in front of the executor, this middleware registers first and wraps outermost, so
    # on either path the flush runs after Rails has completed the request — connections returned,
    # CurrentAttributes cleared — rather than holding them across a network call.
    class RequestBoundary
      def initialize(app)
        @app = app
      end

      def call(env)
        drop_decision
        scope = Langsys.begin_request_scope
        if (finished = env["rack.response_finished"])
          finished << ->(*) { complete(scope) }
          return @app.call(env)
        end

        status, headers, body = serve(env, scope)
        [status, headers, ::Rack::BodyProxy.new(body) { complete(scope) }]
      end

      private

      # With no body there is nothing for the server to close, so a raising application
      # releases its scope here rather than holding its misses until shutdown.
      def serve(env, scope)
        returned = false
        response = @app.call(env)
        returned = true
        response
      ensure
        Langsys.end_request_scope(scope) unless returned
      end

      def drop_decision
        Langsys::Rails.send(:built_client)&.reset_write_decision!
      end

      # Ends the scope before flushing: its misses are released by the end, and this flush
      # is what sends them.
      def complete(scope)
        Langsys.end_request_scope(scope)
        client = Langsys::Rails.send(:built_client)
        return if client.nil?

        begin
          client.flush_pending
        ensure
          client.reset_write_decision!
        end
      end
    end
  end
end
