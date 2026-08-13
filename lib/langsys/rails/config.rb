# frozen_string_literal: true

module Langsys
  module Rails
    # Wrapper configuration, populated from +config.langsys+ in a Rails app (or directly via
    # +Langsys::Rails.configure+). Credentials left +nil+ fall back to the base SDK's
    # +LANGSYS_*+ environment variables.
    class Config
      attr_accessor :api_key, :project_id, :api_url, :base_locale, :supported,
                    :query_param, :cookie_name, :cookie_max_age, :auto_flush,
                    :cache, :cache_ttl, :timeout

      def initialize
        @supported = []
        @query_param = "locale"
        @cookie_name = "langsys_locale"
        @cookie_max_age = 31_536_000 # one year, in seconds
        @auto_flush = true
      end
    end
  end
end
