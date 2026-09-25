# frozen_string_literal: true

require "langsys"

require_relative "rails/version"
require_relative "rails/config"
require_relative "rails/current_locale"
require_relative "rails/helper"
require_relative "rails/controller"
require_relative "rails/request_boundary"
require_relative "rails/messages"
require_relative "rails/validator_source"
require_relative "rails/i18n_bridge"

module Langsys
  # Rails integration for Langsys — a thin wrapper over the +langsys+ base gem.
  #
  # Configure in +config/initializers/langsys.rb+ (or per environment)::
  #
  #   Rails.application.config.langsys.api_key    = ENV["LANGSYS_API_KEY"]
  #   Rails.application.config.langsys.project_id = ENV["LANGSYS_PROJECT_ID"]
  #
  # Then translate in views with +ls+, in controllers with +Langsys::Rails.t+, or reach the
  # full SDK via +Langsys::Rails.client+.
  module Rails
    class << self
      def configure
        yield config if block_given?
        reset_client!
        config
      end

      def config
        @config ||= Config.new
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

      private

      # The client if one has been built, without building one. The request boundary reads it:
      # a request that never translated has nothing to reset or flush, and building a client
      # there would raise on every route of an app that has no credentials yet.
      def built_client
        @client
      end

      def rails_logger
        defined?(::Rails) && ::Rails.respond_to?(:logger) ? ::Rails.logger : nil
      end

      # The logger falls back to Rails.logger so the base SDK's diagnostics reach the
      # application log — among them its one-time warning that this session cannot write
      # (OBS-1), otherwise the only sign that a read-only deployment registers nothing.
      def build_client
        options = config.core_options
        options[:logger] ||= rails_logger
        Langsys::Client.new(locale_source: CurrentAttributesLocaleSource.new, **options)
      end
    end
  end
end

require_relative "rails/railtie" if defined?(::Rails::Railtie)
