# frozen_string_literal: true

require "date"

module Langsys
  module Rails
    # ActiveModel validation failures as Langsys server-message entries (MSG-1..11).
    #
    # An entry is built from the rule that failed and its options — +errors.details+ — never
    # from the message Rails rendered (MSG-9). The rule picks a code from the shared vocabulary
    # and a template from the wording below; the field's label from +human_attribute_name+ is
    # written into the sentence (MSG-3, MSG-10), and only non-translatable values — numbers,
    # dates — travel as +{name}+ markers (MSG-4, MSG-11). Each entry goes through the base
    # SDK's +emit_message+, which builds it and registers a template the catalog lacks once the
    # response is out (MSG-8).
    #
    # The wording is the reference's (langsys4 RuleWording) for every rule it covers, and the
    # spec's MSG-2 table (8.2.13) for an exclusive upper bound; a rule neither covers carries a
    # template of the same shape here. A failure with no rule — a message string, or a symbol
    # this table does not know — becomes code +invalid+ with its full message as the template.
    module Messages
      # Rails error type => [code, template]. +:attribute+ is replaced by the label.
      PLAIN = {
        blank: ["required", "The :attribute is required."],
        empty: ["required", "The :attribute must not be empty."],
        accepted: ["required", "The :attribute must be accepted."],
        present: ["not_allowed", "The :attribute must be blank."],
        inclusion: ["invalid_option", "The selected :attribute is invalid."],
        exclusion: ["invalid_option", "The :attribute is reserved."],
        invalid: ["invalid_format", "The :attribute format is invalid."],
        taken: ["already_taken", "The :attribute has already been taken."],
        confirmation: ["mismatch", "The :attribute confirmation does not match."],
        not_a_number: ["invalid_type", "The :attribute must be a number."],
        not_an_integer: ["invalid_type", "The :attribute must be a whole number."],
        odd: ["invalid_format", "The :attribute must be an odd number."],
        even: ["invalid_format", "The :attribute must be an even number."],
        equal_to: ["mismatch", "The :attribute must be equal to {value}."],
        other_than: ["not_allowed", "The :attribute must be other than {value}."]
      }.freeze

      # Length rules, by the value's type. The count fills the marker.
      SIZED = {
        too_short: {
          string: ["too_short", "The :attribute must be at least {min} characters.", :min],
          list: ["too_few", "The :attribute must have at least {min} items.", :min]
        },
        too_long: {
          string: ["too_long", "The :attribute must not be longer than {max} characters.", :max],
          list: ["too_many", "The :attribute must not have more than {max} items.", :max]
        },
        wrong_length: {
          string: [%w[too_short too_long], "The :attribute must be {size} characters.", :size],
          list: [%w[too_few too_many], "The :attribute must have {size} items.", :size]
        }
      }.freeze

      # Bounds, for a number and for a date. An inclusive bound reuses the reference's min and
      # max wording (MSG-2); an exclusive upper bound is MSG-2's `lt` row.
      COMPARED = {
        greater_than: {
          number: ["too_small", "The :attribute must be greater than {value}.", :value],
          date: ["invalid_date", "The :attribute must be after {date}.", :date]
        },
        greater_than_or_equal_to: {
          number: ["too_small", "The :attribute must be at least {min}.", :min],
          date: ["invalid_date", "The :attribute must be on or after {date}.", :date]
        },
        less_than: {
          number: ["too_large", "The :attribute must be less than {value}.", :value],
          date: ["invalid_date", "The :attribute must be before {date}.", :date]
        },
        less_than_or_equal_to: {
          number: ["too_large", "The :attribute must not be greater than {max}.", :max],
          date: ["invalid_date", "The :attribute must be on or before {date}.", :date]
        }
      }.freeze

      RANGE = [%w[too_small too_large], "The :attribute must be between {min} and {max}."].freeze

      module_function

      # Entries for every failure on +errors+ (an ActiveModel::Errors, or anything responding
      # to +errors+), in the order Rails recorded them.
      def entries(errors, client: Langsys::Rails.client)
        errors = errors.errors unless errors.respond_to?(:each) && errors.respond_to?(:details)
        errors.map do |error|
          code, template, params = wording(error)
          client.emit_message(code: code, template: template, params: params, field: field_path(error.attribute))
        end
      end

      # [code, template, params] for one ActiveModel::Error.
      def wording(error)
        type = error.type
        label = label_for(error)
        return text_only(error) unless type.is_a?(Symbol)

        if PLAIN.key?(type)
          code, template = PLAIN.fetch(type)
          [code, write_label(template, label), value_params(template, error.options[:count])]
        elsif SIZED.key?(type)
          sized(error, type, label)
        elsif COMPARED.key?(type)
          compared(error, type, label)
        elsif type == :in
          ranged(error, label)
        else
          text_only(error)
        end
      end

      # Every template a failure of +type+ on +attribute+ of +klass+ can produce, for the
      # build-time listing (MSG-7). +kind+ is :string, :list, :number, :date, or :either when the
      # declaration cannot say whether a length rule measures text or a list.
      def templates_for(type, label, kind)
        if PLAIN.key?(type)
          [write_label(PLAIN.fetch(type)[1], label)]
        elsif SIZED.key?(type)
          kinds = { list: %i[list], either: %i[string list] }.fetch(kind, %i[string])
          kinds.map { |k| write_label(SIZED.fetch(type).fetch(k)[1], label) }
        elsif COMPARED.key?(type)
          [write_label(COMPARED.fetch(type).fetch(kind == :date ? :date : :number)[1], label)]
        elsif type == :in
          [write_label(RANGE[1], label)]
        else
          []
        end
      end

      def sized(error, type, label)
        kind = list?(value_of(error)) ? :list : :string
        code, template, marker = SIZED.fetch(type).fetch(kind)
        count = error.options[:count]
        if code.is_a?(Array)
          actual = value_of(error).respond_to?(:size) ? value_of(error).size : 0
          code = actual < count.to_i ? code[0] : code[1]
        end
        [code, write_label(template, label), { marker.to_s => number(count) }]
      end

      def compared(error, type, label)
        bound = error.options[:count]
        kind = date?(bound) ? :date : :number
        code, template, marker = COMPARED.fetch(type).fetch(kind)
        [code, write_label(template, label), { marker.to_s => kind == :date ? bound.iso8601 : number(bound) }]
      end

      def ranged(error, label)
        range = error.options[:count]
        codes, template = RANGE
        value = value_of(error)
        code = value.is_a?(Numeric) && value < range.begin ? codes[0] : codes[1]
        [code, write_label(template, label), { "min" => number(range.begin), "max" => number(range.end) }]
      end

      # A failure with no rule to read: its rendered sentence is all there is (MSG-9).
      def text_only(error)
        entry = Langsys::Messages.from_text(error.full_message)
        [entry["code"], entry["template"], nil]
      end

      # The label written into the sentence. A confirmation failure sits on
      # +password_confirmation+ but names +password+; Rails passes that label as :attribute.
      def label_for(error)
        return error.options[:attribute].to_s if error.type == :confirmation && error.options[:attribute]

        klass = error.base.class
        klass.respond_to?(:human_attribute_name) ? klass.human_attribute_name(error.attribute) : error.attribute.to_s
      end

      def write_label(template, label)
        template.gsub(":attribute", label)
      end

      def value_params(template, count)
        template.include?("{value}") ? { "value" => number(count) } : nil
      end

      # "items[3].label" is items.3.label; :base is a whole-record failure, with no field.
      def field_path(attribute)
        return nil if attribute.to_s == "base"

        attribute.to_s.gsub(/\[(\d+)\]/, '.\1')
      end

      # The failing value, where it can be read: a nested attribute such as "items[0].label"
      # names no method on the record.
      def value_of(error)
        record = error.base
        return nil unless record.respond_to?(error.attribute)

        record.read_attribute_for_validation(error.attribute)
      end

      def list?(value) = value.is_a?(Enumerable) && !value.is_a?(String) && !value.is_a?(Hash)

      def date?(value) = value.is_a?(Date) || value.is_a?(Time) || value.is_a?(DateTime)

      # JSON numbers stay numbers (MSG-4); BigDecimal would serialise as a string.
      def number(value)
        return value.to_f if defined?(BigDecimal) && value.is_a?(BigDecimal)

        value
      end
    end
  end
end
