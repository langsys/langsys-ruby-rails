# frozen_string_literal: true

require "langsys"

module Langsys
  module Rails
    # Resolves the locale for a request from its query param, cookie, then +Accept-Language+
    # header — the same order the other Langsys server-side wrappers use. Pure and
    # Rails-free so it's trivially testable.
    class LocaleResolver
      def initialize(config)
        @config = config
      end

      # Returns +[locale, persist]+. An explicit +?locale=+ choice is persisted to a cookie;
      # a cookie or header match is not (it's already where it should be).
      def resolve(query:, cookie:, accept_language:, client:)
        return [Langsys.canonicalize_locale(query), true] if present?(query)
        return [Langsys.canonicalize_locale(cookie), false] if present?(cookie)

        supported = @config.supported.empty? ? nil : @config.supported
        [client.detect_preferred_locale(accept_language, supported) || "", false]
      end

      private

      def present?(value)
        !value.nil? && !value.to_s.empty?
      end
    end
  end
end
