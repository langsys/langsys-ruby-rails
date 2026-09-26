# frozen_string_literal: true

require "active_support/concern"

require_relative "helper"

module Langsys
  module Rails
    # Controller concern (auto-included into +ActionController::Base+ by the Railtie).
    #
    # The locale the app sets on I18n is the request's locale (see CurrentAttributesLocaleSource).
    # For an app that sets none, before each action it asks the base SDK for one (SRV-6): the URL
    # parameter, then the locale cookie, then +Accept-Language+, each validated against the
    # project's locales, falling back to the base locale. After the action it names what that choice
    # depended on in +Vary+, and remembers an explicit URL choice in the cookie. A locale that did
    # not come from the URL is never written back, so an unsupported cookie is never re-set.
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
        cfg = Langsys::Rails.config
        @_langsys_locale = Langsys::Rails.client.resolve_request_locale(
          url: params[cfg.query_param],
          cookie: cookies[cfg.cookie_name],
          accept_language: request.headers["Accept-Language"]
        )
        locale = @_langsys_locale[:locale]
        Langsys::Rails::CurrentLocale.locale = locale unless locale.to_s.empty?
      end

      # A locale the app resolved is the app's to vary on and to remember (SRV-6); the binding adds
      # nothing to it.
      def persist_langsys_locale
        resolved = @_langsys_locale
        return if resolved.nil? || Langsys::Rails::CurrentLocale.framework_resolved

        add_langsys_vary(resolved[:vary])
        return unless resolved[:source] == :url

        remember_langsys_locale(resolved[:locale])
      end

      def remember_langsys_locale(locale)
        cfg = Langsys::Rails.config
        return if cookies[cfg.cookie_name] == locale

        cookies[cfg.cookie_name] = { value: locale, expires: cfg.cookie_max_age.seconds.from_now, same_site: :lax }
      end

      def add_langsys_vary(names)
        present = langsys_vary_names
        added = Array(names).reject { |name| present.any? { |have| have.casecmp?(name) } }
        response.headers["Vary"] = [*present, *added].join(", ") if added.any?
      end

      def langsys_vary_names
        response.headers["Vary"].to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end
  end
end
