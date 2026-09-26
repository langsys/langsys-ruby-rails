# frozen_string_literal: true

require "date"

module Langsys
  module Rails
    # ActiveModel validation failures as Langsys server-message entries (MSG-1..11).
    #
    # The sentence is Rails' own. For each failure ActiveModel is asked for its message before
    # the values are filled — the same lookup, defaults chain and plural choice it uses to render
    # the error, with interpolation skipped — and for the full message around it, so the field's
    # label is written in exactly where Rails writes it. What Rails would interpolate becomes the
    # entry's params: a label (+%{attribute}+, +%{model}+) is written into the sentence, and every
    # other value — a count, the user's input, an app's own interpolation key — becomes a +{name}+
    # marker (MSG-3, MSG-4, MSG-9). The code is Rails' own error key, passed through; a failure
    # that is only text carries none (MSG-2). The field is Rails' attribute, unchanged (MSG-1).
    #
    # Each entry goes through the base SDK's +emit_message+, which builds it and registers a
    # template the catalog lacks once the response is out (MSG-8).
    module Messages
      # Rails' interpolations that name a label, written into the sentence.
      LABELS = %w[attribute model].freeze
      PLACEHOLDER = /%\{([a-z][a-z0-9_]*)\}/

      module_function

      # Entries for every failure on +errors+ (an ActiveModel::Errors, or anything responding
      # to +errors+), in the order Rails recorded them.
      def entries(errors, client: Langsys::Rails.client)
        errors = errors.errors unless errors.respond_to?(:objects)
        errors.objects.map do |error|
          code, template, params = unfilled(error)
          client.emit_message(code: code, template: template, params: params, field: error.attribute.to_s)
        end
      end

      # [code, template, params] for one ActiveModel::Error. A nested error — an associated
      # record's failure imported under a path such as +items[3].label+ — is worded from the
      # record that failed and labelled for the path it is reported under, as Rails renders it.
      def unfilled(error)
        return [nil, error.full_message, nil] unless error.raw_type.is_a?(Symbol)

        failed = error.respond_to?(:inner_error) ? error.inner_error : error
        options = error.options.except(*ActiveModel::Error::CALLBACKS_OPTIONS)
        message = ActiveModel::Error.generate_message(failed.attribute, failed.raw_type, failed.base,
                                                      options.merge(skip_interpolation: true))
        sentence = ActiveModel::Error.full_message(error.attribute, message, error.base)
        template, params = markers(sentence, error, failed, options)
        [error.raw_type.to_s, template, params]
      end

      # Writes labels in and turns every other interpolation into a {name} marker, collecting the
      # value each marker stands for.
      def markers(sentence, error, failed, options)
        params = {}
        template = sentence.gsub(PLACEHOLDER) do
          name = Regexp.last_match(1)
          next label(name, error, options) if LABELS.include?(name)

          params[name] = param(name, failed, options)
          "{#{name}}"
        end
        [template, params.empty? ? nil : params]
      end

      # What Rails would have written for a label placeholder: the confirmed field's label that a
      # confirmation failure passes as :attribute, the field's own label, or the model's name.
      def label(name, error, options)
        return error.base.class.model_name.human if name == "model"

        (options[:attribute] || error.base.class.human_attribute_name(error.attribute)).to_s
      end

      def param(name, error, options)
        return value_of(error) if name == "value" && !options.key?(:value)

        normalise(options[name.to_sym])
      end

      # The failing value, as ActiveModel reads it for +%{value}+.
      def value_of(error)
        return nil if error.attribute == :base || !error.base.respond_to?(error.attribute)

        normalise(error.base.read_attribute_for_validation(error.attribute))
      end

      # JSON numbers stay numbers (MSG-4); a date travels as an ISO date.
      def normalise(value)
        return value.to_f if defined?(BigDecimal) && value.is_a?(BigDecimal)
        return value.iso8601 if value.is_a?(Date) || value.is_a?(Time)

        value
      end
    end
  end
end
