# frozen_string_literal: true

require "active_support/concern"

require_relative "helper"

module Langsys
  module Rails
    # Controller concern (auto-included into +ActionController::Base+ by the Railtie).
    # Resolves the request locale before each action, persists an explicit +?locale=+ choice
    # to a cookie, and — with a write key — registers phrases discovered while rendering.
    #
    # +CurrentLocale+ is reset automatically at request end, so there's nothing to tear down.
    module Controller
      extend ActiveSupport::Concern

      include Helper

      included do
        before_action :set_langsys_locale
        after_action :persist_langsys_locale
        after_action :flush_langsys_pending
        helper_method :ls if respond_to?(:helper_method)
      end

      private

      def set_langsys_locale
        locale, persist = resolve_langsys_locale
        Langsys::Rails::CurrentLocale.locale = locale unless locale.to_s.empty?
        @_langsys_persist_locale = persist && !locale.to_s.empty? ? locale : nil
      end

      def resolve_langsys_locale
        cfg = Langsys::Rails.config
        Langsys::Rails.resolver.resolve(
          query: params[cfg.query_param],
          cookie: cookies[cfg.cookie_name],
          accept_language: request.headers["Accept-Language"],
          client: Langsys::Rails.client
        )
      end

      def persist_langsys_locale
        return if @_langsys_persist_locale.nil?

        cfg = Langsys::Rails.config
        cookies[cfg.cookie_name] = {
          value: @_langsys_persist_locale,
          expires: cfg.cookie_max_age.seconds.from_now,
          same_site: :lax
        }
      end

      def flush_langsys_pending
        Langsys::Rails.handle_pending
      end
    end
  end
end
