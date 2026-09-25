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
      CORE_SETTINGS = %i[
        api_key project_id api_url base_locale cache cache_ttl timeout auto_flush logger
        messages_category migration migration_locale
      ].freeze

      # Where Rails keeps the values SRV-6's locale resolution reads: the URL parameter, and the
      # cookie that remembers an explicit choice. Wiring, not behaviour — the order, validation and
      # Vary are the base SDK's resolve_request_locale.
      WIRING_SETTINGS = %i[query_param cookie_name cookie_max_age].freeze

      attr_accessor(*CORE_SETTINGS, *WIRING_SETTINGS)

      def initialize
        @auto_flush = false
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
