# frozen_string_literal: true

require "active_support"
require "active_support/current_attributes"
require "i18n"

module Langsys
  module Rails
    # The per-request locale the binding resolved itself, and whether a lookup this request was
    # answered from the locale the app set instead. +ActiveSupport::CurrentAttributes+ is reset
    # automatically at the end of every request (and between test cases), so a single shared
    # client is safe across concurrent requests without any manual teardown.
    class CurrentLocale < ActiveSupport::CurrentAttributes
      attribute :locale, :framework_resolved
    end

    # A base-SDK +LocaleSource+ (responds to +get+ / +subscribe+). The client only reads it, so
    # the shared instance always sees the current request's locale.
    #
    # SRV-6: the locale the app set on I18n is the request's locale, mapped and validated by the
    # base SDK (+es_ES+ is +es-es+, a bare +es+ the project's default Spanish, an unsupported one
    # the base). It is read here, at lookup time, because apps set it in callbacks that run after
    # the binding's own. Only when the app has set nothing does the binding's own resolution —
    # URL parameter, cookie, +Accept-Language+ — answer.
    class CurrentAttributesLocaleSource
      # Returns "" when nothing is resolved, so the SDK falls back to the base locale.
      def get
        framework = app_locale
        return CurrentLocale.locale || "" if framework.nil?

        CurrentLocale.framework_resolved = true
        Langsys::Rails.client.framework_locale(framework.to_s)
      end

      def subscribe(callback = nil, &block)
        cb = callback || block
        cb.call(get)
        -> {} # server-rendered: nothing to unsubscribe
      end

      private

      # The locale the app set with +I18n.locale=+ or +I18n.with_locale+, or nil when it set none.
      # +I18n.locale+ itself answers the default locale when none was set, which would read as a
      # choice the app never made; the i18n gem keeps only an explicitly set locale on its config.
      # While a view renders, ActionView stands its I18nProxy in for that config; the app's is the
      # one it wraps.
      def app_locale
        config = I18n.config
        config = config.original_config if config.respond_to?(:original_config)
        config.instance_variable_get(:@locale)
      end
    end
  end
end
