# frozen_string_literal: true

module Langsys
  module Rails
    # MSG-7's source for an ActiveModel app: every template its validators can emit, with each
    # field's label written in, for the base SDK's Langsys::Messages::Command to list and register.
    #
    # It reports, so the command exits non-zero, every message it cannot list ahead of time:
    #
    # * a validated field with no declared label (MSG-10) — a humanised key is a guess, and a
    #   raw key in a sentence is how +cc_number+ reaches a user;
    # * a custom validator class, or a +validate+ method or block, whose templates the model has
    #   not declared. A model declares them by defining +langsys_message_templates+, returning
    #   +{ field => [template, …] }+ (+:base+ for a whole-record failure).
    class ValidatorSource
      KNOWN = {
        "ActiveModel::Validations::PresenceValidator" => ->(_) { [:blank] },
        "ActiveRecord::Validations::PresenceValidator" => ->(_) { [:blank] },
        "ActiveModel::Validations::AbsenceValidator" => ->(_) { [:present] },
        "ActiveRecord::Validations::AbsenceValidator" => ->(_) { [:present] },
        "ActiveModel::Validations::AcceptanceValidator" => ->(_) { [:accepted] },
        "ActiveModel::Validations::ConfirmationValidator" => ->(_) { [:confirmation] },
        "ActiveModel::Validations::InclusionValidator" => ->(_) { [:inclusion] },
        "ActiveModel::Validations::ExclusionValidator" => ->(_) { [:exclusion] },
        "ActiveModel::Validations::FormatValidator" => ->(_) { [:invalid] },
        "ActiveRecord::Validations::UniquenessValidator" => ->(_) { [:taken] },
        "ActiveRecord::Validations::AssociatedValidator" => ->(_) { [:invalid] },
        "ActiveModel::Validations::LengthValidator" => lambda { |options|
          { minimum: :too_short, maximum: :too_long, is: :wrong_length }.filter_map do |k, type|
            type if options.key?(k)
          end
        },
        "ActiveRecord::Validations::LengthValidator" => lambda { |options|
          { minimum: :too_short, maximum: :too_long, is: :wrong_length }.filter_map do |k, type|
            type if options.key?(k)
          end
        },
        "ActiveModel::Validations::NumericalityValidator" => lambda { |options|
          types = [:not_a_number]
          types << :not_an_integer if options[:only_integer]
          types + (%i[greater_than greater_than_or_equal_to less_than less_than_or_equal_to equal_to other_than odd
                      even in] &
                   options.keys)
        },
        "ActiveRecord::Validations::NumericalityValidator" => lambda { |options|
          types = [:not_a_number]
          types << :not_an_integer if options[:only_integer]
          types + (%i[greater_than greater_than_or_equal_to less_than less_than_or_equal_to equal_to other_than odd
                      even in] &
                   options.keys)
        },
        "ActiveModel::Validations::ComparisonValidator" => lambda { |options|
          %i[greater_than greater_than_or_equal_to less_than less_than_or_equal_to equal_to other_than] & options.keys
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
        validated = Hash.new { |h, k| h[k] = [] }
        custom = []
        klass.validators.each do |validator|
          known = KNOWN[validator.class.name]
          if known.nil?
            custom << "#{validator.class.name} on #{validator.attributes.join(', ')}"
            next
          end
          validator.attributes.each { |attribute| validated[attribute.to_sym].concat(known.call(validator.options)) }
        end
        custom.concat(custom_callbacks(klass))

        validated.each { |attribute, types| collect_attribute(klass, attribute, types.uniq, catalog) }
        collect_declared(klass, custom, catalog)
      end

      def collect_attribute(klass, attribute, types, catalog)
        unless label_declared?(klass, attribute)
          problem(catalog, klass, attribute, "no label is declared for this validated field",
                  "add #{label_key(klass, attribute)} to your locale file, the label human_attribute_name reads")
          return
        end

        label = klass.human_attribute_name(attribute)
        types.each do |type|
          field = type == :confirmation ? "#{attribute}_confirmation" : attribute.to_s
          Langsys::Rails::Messages.templates_for(type, label, kind(klass, attribute)).each do |template|
            catalog.add(template, source: klass.name, field: field)
          end
        end
      end

      def collect_declared(klass, custom, catalog)
        if klass.respond_to?(:langsys_message_templates)
          klass.langsys_message_templates.each do |field, templates|
            Array(templates).each { |template| catalog.add(template, source: klass.name, field: field.to_s) }
          end
        else
          custom.each do |rule|
            problem(catalog, klass, nil, "custom rule #{rule} has no declared templates",
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

      # What a length or bound rule measures, as far as the declaration says. An attribute whose
      # type does not settle it (untyped, JSON) is :either, and both wordings are listed; the one
      # emitted at runtime is chosen from the value.
      def kind(klass, attribute)
        return :list if klass.respond_to?(:reflect_on_association) && klass.reflect_on_association(attribute)
        return :either unless klass.respond_to?(:type_for_attribute)

        type = klass.type_for_attribute(attribute.to_s)
        return :list if type.respond_to?(:subtype) || type.class.name.to_s.end_with?("::Array")

        case type.type
        when :date, :datetime, :time then :date
        when :string, :text then :string
        when :integer, :float, :decimal then :number
        else :either
        end
      end

      def label_declared?(klass, attribute)
        return false unless klass.respond_to?(:human_attribute_name) && klass.respond_to?(:lookup_ancestors)

        keys = klass.lookup_ancestors.map do |ancestor|
          :"#{klass.i18n_scope}.attributes.#{ancestor.model_name.i18n_key}.#{attribute}"
        end
        (keys + [:"attributes.#{attribute}"]).any? { |key| I18n.exists?(key, locale: I18n.default_locale) }
      end

      def label_key(klass, attribute)
        return "a human_attribute_name label for #{attribute}" unless klass.respond_to?(:model_name)

        "#{I18n.default_locale}.#{klass.i18n_scope}.attributes.#{klass.model_name.i18n_key}.#{attribute}"
      end

      def problem(catalog, klass, field, issue, fix)
        catalog.problem(source: klass.name, field: field&.to_s, issue: issue, fix: fix)
      end
    end
  end
end
