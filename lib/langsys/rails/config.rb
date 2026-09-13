# frozen_string_literal: true

module Langsys
  module Rails
    # Wrapper configuration, populated from +config.langsys+ in a Rails app (or directly via
    # +Langsys::Rails.configure+). Credentials left +nil+ fall back to the base SDK's
    # +LANGSYS_*+ environment variables.
    class Config
      # Settings the base SDK's client defines. Each reaches +Langsys::Client.new+ under the same
      # keyword, unchanged, and defaults to the base SDK's own default — except +logger+, which
      # falls back to Rails.logger so the base SDK's diagnostics land in the application log.
      CORE_SETTINGS = %i[api_key project_id api_url base_locale cache cache_ttl timeout auto_flush logger].freeze

      # How a Rails request maps to a locale. +supported+ is the base SDK's own
      # +detect_preferred_locale+ parameter; the other three have no base-SDK equivalent and are
      # held pending the program's ambient-locale ruling (see CONFORMANCE.md, BIND-4).
      LOCALE_SETTINGS = %i[supported query_param cookie_name cookie_max_age].freeze

      attr_accessor(*CORE_SETTINGS, *LOCALE_SETTINGS)

      def initialize
        @auto_flush = false
        @supported = []
        @query_param = "locale"
        @cookie_name = "langsys_locale"
        @cookie_max_age = 31_536_000 # one year, in seconds
      end

      def core_options
        CORE_SETTINGS.to_h { |name| [name, public_send(name)] }
      end
    end
  end
end
