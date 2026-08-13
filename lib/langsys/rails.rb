# frozen_string_literal: true

require "langsys"

require_relative "rails/version"
require_relative "rails/config"
require_relative "rails/current_locale"
require_relative "rails/locale_resolver"
require_relative "rails/helper"
require_relative "rails/controller"

module Langsys
  # Rails integration for Langsys — a thin wrapper over the +langsys+ base gem.
  #
  # Configure in +config/initializers/langsys.rb+ (or per environment)::
  #
  #   Rails.application.config.langsys.api_key    = ENV["LANGSYS_API_KEY"]
  #   Rails.application.config.langsys.project_id = ENV["LANGSYS_PROJECT_ID"]
  #   Rails.application.config.langsys.supported  = %w[en-US es-ES]
  #
  # Then translate in views with +ls+, in controllers with +Langsys::Rails.t+, or reach the
  # full SDK via +Langsys::Rails.client+.
  module Rails
    class << self
      def configure
        yield config if block_given?
        @resolver = nil
        reset_client!
        config
      end

      def config
        @config ||= Config.new
      end

      def resolver
        @resolver ||= LocaleResolver.new(config)
      end

      # The process-wide client (built once). Its locale comes from the request-scoped
      # +CurrentLocale+, so the shared instance is safe across concurrent requests.
      def client
        @client ||= build_client
      end

      # Inject a caller-built client (advanced setups / tests). It should read its locale
      # from +CurrentAttributesLocaleSource+ to stay request-safe.
      attr_writer :client

      def reset_client!
        @client = nil
      end

      # Translate for the current request locale. +Langsys::Rails.t("Hello, {name}!",
      # "Greetings", name: "Sarah")+ — keyword args become interpolation params.
      def t(phrase, category = nil, **params)
        client.translate(phrase, category: category, params: params.empty? ? nil : params)
      end

      # The locale resolved for the current request (canonical), or "" before resolution.
      def locale
        client.locale
      end

      # Register phrases discovered while rendering (write key + auto_flush), or drop the
      # queue (read key) so a long-running server doesn't accumulate it. Never raises.
      def handle_pending
        return unless client.has_pending?

        if config.auto_flush && client.can_write?
          client.flush_pending
        else
          client.clear_pending
        end
      rescue Langsys::Error => e
        logger&.warn("langsys: flushing pending registrations failed: #{e.message}")
        nil
      end

      private

      def logger
        defined?(::Rails) && ::Rails.respond_to?(:logger) ? ::Rails.logger : nil
      end

      def build_client
        Langsys::Client.new(
          api_key: config.api_key,
          project_id: config.project_id,
          api_url: config.api_url,
          base_locale: config.base_locale,
          locale_source: CurrentAttributesLocaleSource.new,
          cache: config.cache,
          cache_ttl: config.cache_ttl,
          timeout: config.timeout
        )
      end
    end
  end
end

require_relative "rails/railtie" if defined?(::Rails::Railtie)
