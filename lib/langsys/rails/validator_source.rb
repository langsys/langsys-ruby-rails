# frozen_string_literal: true

module Langsys
  module Rails
    # MSG-7's source for an ActiveModel app: every template its validators can emit — Rails' own
    # sentence for each failure, built exactly as a failure at runtime builds it, with the field's
    # label written in — for the base SDK's Langsys::Messages::Command to list and register.
    #
    # It reports what it cannot list ahead of time, each with what would make it listable: a
    # custom validator class, a +validate+ method or block, or a message or bound built by a proc
    # at runtime. Those register when first emitted (MSG-8), so they fail the command only under
    # its strict flag. A validated field with no declared label is advice and never fails (MSG-10):
    # Rails prints a name it derives from the key, which is sometimes one the app would rather not
    # show. A model lists its custom rules' templates by defining +langsys_message_templates+,
    # returning +{ field => [template, …] }+.
    class ValidatorSource
      SIZE = { minimum: :too_short, maximum: :too_long, is: :wrong_length }.freeze
      BOUNDS = %i[greater_than greater_than_or_equal_to less_than less_than_or_equal_to equal_to other_than].freeze

      # validator class name => ->(options) { [[error type, error options], …] }
      KNOWN = {
        "PresenceValidator" => ->(_) { [[:blank, {}]] },
        "AbsenceValidator" => ->(_) { [[:present, {}]] },
        "AcceptanceValidator" => ->(_) { [[:accepted, {}]] },
        "ConfirmationValidator" => ->(_) { [[:confirmation, {}]] },
        "InclusionValidator" => ->(_) { [[:inclusion, {}]] },
        "ExclusionValidator" => ->(_) { [[:exclusion, {}]] },
        "FormatValidator" => ->(_) { [[:invalid, {}]] },
        "UniquenessValidator" => ->(_) { [[:taken, {}]] },
        "AssociatedValidator" => ->(_) { [[:invalid, {}]] },
        "LengthValidator" => ->(o) { SIZE.filter_map { |key, type| [type, { count: o[key] }] if o.key?(key) } },
        "ComparisonValidator" => ->(o) { (BOUNDS & o.keys).map { |key| [key, { count: o[key] }] } },
        "NumericalityValidator" => lambda { |o|
          [[:not_a_number, {}]] + (o[:only_integer] ? [[:not_an_integer, {}]] : []) +
            ((BOUNDS + %i[in]) & o.keys).map { |key| [key, { count: o[key] }] } +
            (%i[odd even] & o.keys).map { |key| [key, {}] }
        }
      }.freeze

      # Validation callbacks Rails adds itself, whose failures surface through a known validator.
      INTERNAL_CALLBACK = /\Avalidate_associated_records_for_/

      attr_reader :name

      def initialize(classes = nil)
        @classes = classes
        @name = "Rails validators"
      end

      def collect(catalog)
        classes.each { |klass| collect_class(klass, catalog) }
        catalog
      end

      private

      def classes
        return @classes if @classes

        ObjectSpace.each_object(Class).select do |klass|
          klass.name && klass.include?(ActiveModel::Validations) && !klass.validators.empty?
        end.sort_by(&:name)
      end

      def collect_class(klass, catalog)
        record = klass.new
        custom = custom_callbacks(klass)
        klass.validators.each do |validator|
          failures = KNOWN[validator.class.name.demodulize]
          if failures.nil?
            custom << "#{validator.class.name} on #{validator.attributes.join(', ')}"
            next
          end
          validator.attributes.each do |attribute|
            collect_failures(klass, record, attribute, validator.options, failures.call(validator.options), catalog)
          end
        end
        collect_declared(klass, custom, catalog)
      end

      def collect_failures(klass, record, attribute, options, failures, catalog)
        advise_label(klass, attribute, catalog)
        failures.each do |type, error_options|
          field, error_options = confirmation(klass, attribute, error_options) if type == :confirmation
          if options[:message].respond_to?(:call) || runtime_bound?(error_options[:count])
            problem(catalog, klass, attribute, "the #{type} message is built at runtime",
                    "give the validator a literal message and bound, or declare it in langsys_message_templates")
            next
          end
          error = ActiveModel::Error.new(record, (field || attribute).to_sym, type,
                                         **error_options, **options.slice(:message))
          catalog.add(Langsys::Rails::Messages.unfilled(error)[1], source: klass.name, field: (field || attribute).to_s)
        end
      end

      def confirmation(klass, attribute, error_options)
        [:"#{attribute}_confirmation", error_options.merge(attribute: klass.human_attribute_name(attribute))]
      end

      # A proc, or a method name, is a bound only known when the record is validated.
      def runtime_bound?(value) = value.respond_to?(:call) || value.is_a?(Symbol)

      def collect_declared(klass, custom, catalog)
        if klass.respond_to?(:langsys_message_templates)
          klass.langsys_message_templates.each do |field, templates|
            Array(templates).each { |template| catalog.add(template, source: klass.name, field: field.to_s) }
          end
        else
          custom.each do |rule|
            problem(catalog, klass, nil, "custom rule #{rule} has no listed templates",
                    "define #{klass.name}.langsys_message_templates returning { field => [template, ...] }")
          end
        end
      end

      def custom_callbacks(klass)
        return [] unless klass.respond_to?(:_validate_callbacks)

        klass._validate_callbacks.filter_map do |callback|
          filter = callback.filter
          case filter
          when Symbol then "validate :#{filter}" unless filter.to_s.match?(INTERNAL_CALLBACK)
          when Proc then "a validate block"
          end
        end
      end

      def advise_label(klass, attribute, catalog)
        return if label_declared?(klass, attribute)

        catalog.problem(source: klass.name, field: attribute.to_s, advice: true,
                        issue: "no label is declared, so Rails prints #{klass.human_attribute_name(attribute).inspect}",
                        fix: "add #{label_key(klass, attribute)} to your locale file if that is not the name to show")
      end

      def label_declared?(klass, attribute)
        keys = klass.lookup_ancestors.map do |ancestor|
          :"#{klass.i18n_scope}.attributes.#{ancestor.model_name.i18n_key}.#{attribute}"
        end
        (keys + [:"attributes.#{attribute}"]).any? { |key| I18n.exists?(key, locale: I18n.default_locale) }
      end

      def label_key(klass, attribute)
        "#{I18n.default_locale}.#{klass.i18n_scope}.attributes.#{klass.model_name.i18n_key}.#{attribute}"
      end

      def problem(catalog, klass, field, issue, fix)
        catalog.problem(source: klass.name, field: field&.to_s, issue: issue, fix: fix)
      end
    end
  end
end
