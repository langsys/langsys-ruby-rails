# frozen_string_literal: true

require "active_support/concern"

require_relative "helper"

module Langsys
  module Rails
    # Controller concern (auto-included into +ActionController::Base+ by the Railtie).
    # Resolves the request locale before each action and persists an explicit +?locale=+
    # choice to a cookie.
    #
    # Phrases discovered while rendering are not registered here: RequestBoundary does that
    # once the response has been sent. +CurrentLocale+ is reset automatically at request end.
    module Controller
      extend ActiveSupport::Concern

      include Helper

      included do
        before_action :set_langsys_locale
        after_action :persist_langsys_locale
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
    end
  end
end
