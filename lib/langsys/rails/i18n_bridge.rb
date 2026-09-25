# frozen_string_literal: true

require "i18n"

module Langsys
  module Rails
    # Legacy-key migration's Rails entry point (MIG-2, MIG-8): +I18n.t+, and the +t+ view helper
    # once ActionView has resolved a lazy +.key+ to its full key, answered by the base SDK.
    #
    # Installed in front of the app's I18n backend only when +config.langsys.migration+ names the
    # kept source file(s) (MIG-1); unset, nothing here runs. A lookup goes to Langsys when
    #
    # * its full key is in the migration files — the key's source value is the phrase; or
    # * it is a literal: a string passed with no scope and no default of the app's own, which no
    #   I18n backend knows — the text is itself the phrase, its +%{name}+ placeholders converted.
    #
    # Everything else — Rails' own keys (+errors.messages.blank+, date formats), scoped and
    # defaulted lookups — goes to the backend it replaced, unchanged. The conversion, the category
    # from the key's namespace, and registration are the base SDK's +translate_legacy+.
    class I18nBridge
      # Keys I18n reserves for itself; everything else in the options is an interpolation value.
      RESERVED = I18n::RESERVED_KEYS + %i[locale]

      def self.install!
        return if I18n.backend.is_a?(self)

        I18n.backend = new(I18n.backend)
      end

      attr_reader :backend

      def initialize(backend)
        @backend = backend
      end

      def translate(locale, key, options = I18n::EMPTY_HASH)
        client = Langsys::Rails.client
        full = full_key(key, options)
        argument = if client.migration&.key?(full) then full
                   elsif literal?(locale, key, options) then key
                   end
        return @backend.translate(locale, key, options) if argument.nil?

        client.translate_legacy(argument, entry_point: :rails, params: params(options))
      end

      def respond_to_missing?(name, include_private = false)
        @backend.respond_to?(name, include_private) || super
      end

      def method_missing(name, ...)
        @backend.respond_to?(name) ? @backend.public_send(name, ...) : super
      end

      private

      def full_key(key, options)
        I18n.normalize_keys(nil, key, options[:scope], options[:separator]).join(".")
      end

      def literal?(locale, key, options)
        key.is_a?(String) && options[:scope].nil? && !app_default?(options[:default]) &&
          !@backend.exists?(locale, key)
      end

      # ActionView's +t+ passes its own sentinel as the default; an app's default is text, a key,
      # a list of either, or a proc.
      def app_default?(default)
        default.is_a?(String) || default.is_a?(Symbol) || default.is_a?(Array) || default.is_a?(Hash) ||
          default.respond_to?(:call)
      end

      def params(options)
        values = options.except(*RESERVED)
        values.empty? ? nil : values
      end
    end
  end
end
