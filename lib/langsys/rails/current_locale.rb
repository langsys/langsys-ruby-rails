# frozen_string_literal: true

require "active_support"
require "active_support/current_attributes"

module Langsys
  module Rails
    # The per-request locale. +ActiveSupport::CurrentAttributes+ is reset automatically at
    # the end of every request (and between test cases), so a single shared client is safe
    # across concurrent requests without any manual teardown.
    class CurrentLocale < ActiveSupport::CurrentAttributes
      attribute :locale
    end

    # A base-SDK +LocaleSource+ (responds to +get+ / +subscribe+) backed by the
    # request-scoped +CurrentLocale+. The client only reads it, so the shared instance
    # always sees the current request's locale.
    class CurrentAttributesLocaleSource
      # Returns "" when unset, so the SDK falls back to the configured / project base locale.
      def get
        CurrentLocale.locale || ""
      end

      def subscribe(callback = nil, &block)
        cb = callback || block
        cb.call(get)
        -> {} # server-rendered: nothing to unsubscribe
      end
    end
  end
end
