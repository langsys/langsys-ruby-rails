# frozen_string_literal: true

# CONF-3 mutation manifest. `rake mutation` runs the hermetic entries, `rake mutation:live` the
# live ones. Each entry breaks one behaviour a CONFORMANCE.md row claims and names the examples
# that must turn red; spec/mutation/harness.rb refuses an entry whose `find` does not occur
# exactly once, whose examples are not green unmutated, or whose mutant breaks loading.
module Mutation
  BOUNDARY = "lib/langsys/rails/request_boundary.rb"
  MODULE = "lib/langsys/rails.rb"
  CONFIG = "lib/langsys/rails/config.rb"
  RAILTIE = "lib/langsys/rails/railtie.rb"
  HELPER = "lib/langsys/rails/helper.rb"
  LOCALE = "lib/langsys/rails/current_locale.rb"
  CONTROLLER = "lib/langsys/rails/controller.rb"
  MESSAGES = "lib/langsys/rails/messages.rb"
  SOURCE = "lib/langsys/rails/validator_source.rb"
  BRIDGE = "lib/langsys/rails/i18n_bridge.rb"

  BOUNDARY_SPEC = "spec/request_boundary_spec.rb"
  BINDING_SPEC = "spec/binding_conformance_spec.rb"
  PROBE_SPEC = "spec/delegation_probe_spec.rb"
  LIVE_SPEC = "spec/integration/live_spec.rb"
  DOC_SPEC = "spec/conformance_doc_spec.rb"
  INTEGRATION_SPEC = "spec/integration_spec.rb"
  MESSAGES_SPEC = "spec/messages_spec.rb"
  BRIDGE_SPEC = "spec/i18n_bridge_spec.rb"
  CONTRACT_SPEC = "spec/contract_spec.rb"

  T_CALL = "        client.translate(phrase, category: category, params: params.empty? ? nil : params)\n"
  FLUSH = "          client.flush_pending\n"
  BODY_PROXY = "        [status, headers, ::Rack::BodyProxy.new(body) { complete(scope) }]\n"
  FINISHED = "        if (finished = env[\"rack.response_finished\"])\n"
  LOGGER_FALLBACK = "        options[:logger] ||= rails_logger\n"
  RECONFIGURE = "        reset_client!\n        config\n"
  RESOLVE = "      def set_langsys_locale\n"
  RAISING_LOOKUP = "#{RESOLVE}        Langsys::Rails.client.get_translations(use_cache: false) || " \
                   "raise(Langsys::Error, \"catalog unavailable\")\n".freeze
  VARY = "        add_langsys_vary(resolved[:vary])\n"
  URL_ONLY = "        return unless resolved[:source] == :url\n"
  MARK = "        locale ? { \"data-ls-resolved\" => locale } : {}\n"
  EMIT = "          client.emit_message(code: code, template: template, params: params, field: field_path(error.attribute))\n"
  LS_LOOKUP = "        Langsys::Rails.client.get_translations" \
              ".dig(category || \"__uncategorized__\", phrase) || phrase\n"

  def self.examples(file, *descriptions)
    [file, *descriptions.flat_map { |description| ["-e", description] }]
  end

  MANIFEST = [
    # -- the request boundary -------------------------------------------------------------
    { id: "boundary-branches-on-capability", rule: "BIND-2", file: BOUNDARY, find: FLUSH,
      replace: "          client.can_write? ? client.flush_pending : client.clear_pending\n",
      examples: [*examples(BOUNDARY_SPEC, "does not discard a read-only session's queue"),
                 PROBE_SPEC, "-e", "capability decision", "-e", "queue bookkeeping"] },
    { id: "boundary-never-flushes", rule: "REG-3", file: BOUNDARY, find: FLUSH, replace: "          nil\n",
      examples: examples(BOUNDARY_SPEC, "on the body-close path") },
    { id: "flush-on-the-request-path", rule: "SRV-3", file: BOUNDARY, find: BODY_PROXY,
      replace: "        complete(scope)\n        [status, headers, body]\n",
      examples: examples(BOUNDARY_SPEC, "on the body-close path", "posts nothing before the response is sent") },
    { id: "response-finished-path-ignored", rule: "SRV-3", file: BOUNDARY, find: FINISHED,
      replace: "        if (finished = nil)\n",
      examples: examples(BOUNDARY_SPEC, "on the rack.response_finished path") },
    { id: "boundary-behind-the-executor", rule: "SRV-3", file: RAILTIE,
      find: "config.app_middleware.insert_before ActionDispatch::Executor, RequestBoundary",
      replace: "config.app_middleware.insert_after ActionDispatch::Executor, RequestBoundary",
      examples: examples(BOUNDARY_SPEC, "sits in front of ActionDispatch::Executor",
                         "only after Rails has completed the request") },
    { id: "no-request-scope", rule: "SRV-3", file: BOUNDARY,
      find: "        scope = Langsys.begin_request_scope\n", replace: "        scope = nil\n",
      examples: examples(BOUNDARY_SPEC, "does not let another request's flush collect a miss") },
    { id: "scope-held-after-error", rule: "SRV-3", file: BOUNDARY,
      find: "        Langsys.end_request_scope(scope) unless returned\n", replace: "        nil\n",
      examples: examples(BOUNDARY_SPEC, "is released when the application raises") },
    { id: "decision-kept-after-request", rule: "GATE-3", file: BOUNDARY,
      find: "          client.reset_write_decision!\n", replace: "          nil\n",
      examples: examples(BOUNDARY_SPEC, "is dropped once the request is done") },
    { id: "decision-kept-into-request", rule: "GATE-3", file: BOUNDARY,
      find: "        Langsys::Rails.send(:built_client)&.reset_write_decision!\n", replace: "        nil\n",
      examples: examples(BOUNDARY_SPEC, "drops a decision recorded outside any request") },
    { id: "boundary-builds-a-client", rule: "WIRE-4", file: BOUNDARY,
      find: "        client = Langsys::Rails.send(:built_client)\n", replace: "        client = Langsys::Rails.client\n",
      examples: examples(BOUNDARY_SPEC, "neither builds a client nor raises") },

    # -- configuration and surface -------------------------------------------------------
    { id: "logger-not-passed", rule: "OBS-1", file: MODULE, find: LOGGER_FALLBACK, replace: "",
      examples: examples(BINDING_SPEC, "logs the once-per-process unusable-capability warning") },
    { id: "binding-only-setting", rule: "BIND-4", file: CONFIG,
      find: "WIRING_SETTINGS = %i[query_param cookie_name cookie_max_age].freeze",
      replace: "WIRING_SETTINGS = %i[query_param cookie_name cookie_max_age discovery].freeze",
      examples: examples(BINDING_SPEC, "adds only SRV-6's wiring") },
    { id: "auto-flush-default-diverges", rule: "BIND-4", file: CONFIG,
      find: "        @auto_flush = false\n", replace: "        @auto_flush = true\n",
      examples: examples(BINDING_SPEC, "gives auto_flush the core's meaning") },
    { id: "core-setting-dropped", rule: "BIND-4", file: CONFIG,
      find: "CORE_SETTINGS.to_h { |name| [name, public_send(name)] }",
      replace: "CORE_SETTINGS.to_h { |name| [name, public_send(name)] }.except(:timeout)",
      examples: examples(BINDING_SPEC, "hands each configured core setting") },
    { id: "lookup-results-memoized", rule: "BIND-5", file: MODULE, find: T_CALL,
      replace: "        (@lookups ||= {})[[phrase, category, params, locale]] ||= " \
               "client.translate(phrase, category: category, params: params.empty? ? nil : params)\n",
      examples: examples(BINDING_SPEC, "shows a changed catalog on the very next call",
                         "memoizes nothing but its own configuration objects") },
    { id: "t-adapts-meaning", rule: "BIND-1", file: MODULE, find: T_CALL,
      replace: "        client.translate(phrase, category: category || \"UI\", params: params.empty? ? nil : params)\n",
      examples: examples(BINDING_SPEC, "renders and queues exactly what calling the core directly does") },
    { id: "new-behaviour-name", rule: "BIND-6", file: MODULE, find: "      def locale\n",
      replace: "      def flush\n        client.flush_pending\n      end\n\n      def locale\n",
      examples: examples(BINDING_SPEC, "exposes the core client by reference") },
    { id: "ls-feeds-no-lane", rule: "GATE-7", file: HELPER,
      find: "        Langsys::Rails.t(phrase, category, **params)\n",
      replace: LS_LOOKUP,
      examples: examples(BINDING_SPEC, "the ls helper in a rendered view queues a miss") },
    { id: "process-global-locale", rule: "SRV-2", file: LOCALE,
      find: "    class CurrentLocale < ActiveSupport::CurrentAttributes\n      attribute :locale\n    end\n",
      replace: "    class CurrentLocale\n      class << self\n        attr_accessor :locale\n\n        " \
               "def reset = @locale = nil\n      end\n    end\n",
      examples: examples(BINDING_SPEC, "serves each of two renders suspended mid-flight") },
    { id: "stale-client-after-redirect", rule: "WIRE-5", file: MODULE, find: RECONFIGURE,
      replace: "        config\n",
      examples: examples(BINDING_SPEC, "sends the next request's lookups to the new base") },
    { id: "raising-lookup-on-request-path", rule: "WIRE-4", file: CONTROLLER, find: RESOLVE,
      replace: RAISING_LOOKUP,
      examples: examples(BINDING_SPEC, "serves the source language and records nothing") },

    # -- locale resolution (SRV-6) and the resolved root (GATE-10) ---------------------------
    { id: "vary-dropped", rule: "SRV-6", file: CONTROLLER, find: VARY, replace: "",
      examples: examples(INTEGRATION_SPEC, "with Vary: Cookie", "with Vary: Accept-Language") },
    { id: "cookie-written-for-any-source", rule: "SRV-6", file: CONTROLLER, find: URL_ONLY, replace: "",
      examples: examples(INTEGRATION_SPEC, "does not re-set the cookie", "lets the cookie win over the header") },
    { id: "root-always-marked", rule: "GATE-10", file: HELPER, find: MARK,
      replace: "        { \"data-ls-resolved\" => Langsys::Rails.client.locale.downcase }\n",
      examples: examples(BINDING_SPEC, "leaves a base-locale render unmarked") },

    # -- server messages ------------------------------------------------------------------------
    { id: "entries-from-rendered-text", rule: "MSG-9", file: MESSAGES,
      find: "          code, template, params = wording(error)\n",
      replace: "          code, template, params = [\"invalid\", error.full_message, nil]\n",
      examples: examples(MESSAGES_SPEC, "yields one entry per failed rule", "never takes a template") },
    { id: "exclusive-bound-worded-as-max", rule: "MSG-2", file: MESSAGES,
      find: "number: [\"too_large\", \"The :attribute must be less than {value}.\", :value],",
      replace: "number: [\"too_large\", \"The :attribute must not be greater than {value}.\", :value],",
      examples: examples(MESSAGES_SPEC, "uses MSG-2's wording for an exclusive upper bound") },
    { id: "size-code-ignores-type", rule: "MSG-2", file: MESSAGES,
      find: "        kind = list?(value_of(error)) ? :list : :string\n", replace: "        kind = :string\n",
      examples: examples(MESSAGES_SPEC, "picks the size code by type") },
    { id: "label-guessed-from-key", rule: "MSG-10", file: MESSAGES,
      find: "klass.respond_to?(:human_attribute_name) ? klass.human_attribute_name(error.attribute) : error.attribute.to_s",
      replace: "error.attribute.to_s.humanize",
      examples: examples(MESSAGES_SPEC, "writes human_attribute_name into the sentence") },
    { id: "params-kept-as-strings", rule: "MSG-4", file: MESSAGES, find: "      def number(value)\n",
      replace: "      def number(value)\n        return value.to_s\n",
      examples: examples(MESSAGES_SPEC, "carries only the fixed keys, numbers as numbers") },
    { id: "unlabelled-field-not-reported", rule: "MSG-7", file: SOURCE,
      find: "        unless label_declared?(klass, attribute)\n", replace: "        if false\n",
      examples: examples(MESSAGES_SPEC, "names a validated field with no declared label") },
    { id: "custom-rule-not-reported", rule: "MSG-7", file: SOURCE,
      find: "        custom.concat(custom_callbacks(klass))\n", replace: "",
      examples: examples(MESSAGES_SPEC, "exits non-zero naming a custom rule") },
    { id: "declared-template-unchecked", rule: "MSG-11", file: SOURCE,
      find: "            Array(templates).each { |template| catalog.add(template, source: klass.name, field: field.to_s) }\n",
      replace: "            Array(templates).each { |template| catalog.templates << template }\n",
      examples: examples(MESSAGES_SPEC, "refuses a declared template carrying a label marker") },
    { id: "message-used-as-lookup-key", rule: "MSG-5", file: HELPER,
      find: "        Langsys::Rails.client.render_message(entry)\n",
      replace: "        Langsys::Rails.t(entry[\"message\"], \"Errors\")\n",
      examples: [*examples(MESSAGES_SPEC, "never looks message up"), CONTRACT_SPEC] },

    # -- legacy-key migration ---------------------------------------------------------------------
    { id: "bridge-installed-unconditionally", rule: "MIG-1", file: RAILTIE,
      find: "        Langsys::Rails::I18nBridge.install! if Langsys::Rails.config.migration\n",
      replace: "        Langsys::Rails::I18nBridge.install!\n",
      examples: examples(BRIDGE_SPEC, "leaves I18n alone") },
    { id: "no-literal-miss", rule: "MIG-2", file: BRIDGE,
      find: "        key.is_a?(String) && options[:scope].nil? && !app_default?(options[:default]) &&\n",
      replace: "        false && options[:scope].nil? && !app_default?(options[:default]) &&\n",
      examples: examples(BRIDGE_SPEC, "treats a literal string as source text") },
    { id: "rails-keys-hijacked", rule: "MIG-2", file: BRIDGE,
      find: "          !@backend.exists?(locale, key)\n", replace: "          true\n",
      examples: examples(BRIDGE_SPEC, "leaves Rails' own keys") },
    { id: "bridge-overrides-category", rule: "MIG-8", file: BRIDGE,
      find: "        client.translate_legacy(argument, entry_point: :rails, params: params(options))\n",
      replace: "        client.translate_legacy(argument, entry_point: :rails, category: \"legacy\", params: params(options))\n",
      examples: examples(BRIDGE_SPEC, "gives a key through I18n.t the same phrase and category") },

    # -- the conformance document --------------------------------------------------------
    { id: "summary-drifts-from-table", rule: "CONF-2", file: "CONFORMANCE.md",
      find: "| implemented | 34 |", replace: "| implemented | 35 |",
      examples: examples(DOC_SPEC, "has a summary computed from the table") },

    # -- live: the same breaks, observed against the real server ---------------------------
    { id: "live-flush-on-the-request-path", rule: "SRV-3", live: true, file: BOUNDARY, find: BODY_PROXY,
      replace: "        complete(scope)\n        [status, headers, body]\n",
      examples: examples(LIVE_SPEC, "registers a render's miss only once the server closes the body") },
    { id: "live-response-finished-ignored", rule: "SRV-3", live: true, file: BOUNDARY, find: FINISHED,
      replace: "        if (finished = nil)\n",
      examples: examples(LIVE_SPEC, "registers a render's miss only once the server runs rack.response_finished") },
    { id: "live-no-request-scope", rule: "SRV-3", live: true, file: BOUNDARY,
      find: "        scope = Langsys.begin_request_scope\n", replace: "        scope = nil\n",
      examples: examples(LIVE_SPEC, "holds a render's miss from another request's flush") },
    { id: "live-vary-dropped", rule: "SRV-6", live: true, file: CONTROLLER, find: VARY, replace: "",
      examples: examples(LIVE_SPEC, "lets the cookie win over the header, with Vary: Cookie") },
    { id: "live-root-always-marked", rule: "GATE-10", live: true, file: HELPER, find: MARK,
      replace: "        { \"data-ls-resolved\" => Langsys::Rails.client.locale.downcase }\n",
      examples: examples(LIVE_SPEC, "marks a page rendered in a target locale") },
    { id: "live-template-never-registered", rule: "MSG-8", live: true, file: MESSAGES, find: EMIT,
      replace: "          Langsys::Messages.entry(code: code, template: template, params: params, field: field_path(error.attribute))\n",
      examples: examples(LIVE_SPEC, "registers a template the catalog lacks under Errors") },
    { id: "live-serves-base-language", rule: "SRV-1", live: true, file: MODULE, find: T_CALL,
      replace: "        client.translate(phrase, category: category, params: params.empty? ? nil : params, " \
               "locale: config.base_locale)\n",
      examples: examples(LIVE_SPEC, "serves the request locale's translation in the response bytes") },
    { id: "live-logger-not-passed", rule: "OBS-1", live: true, file: MODULE, find: LOGGER_FALLBACK, replace: "",
      examples: examples(LIVE_SPEC, "puts the core's unusable-capability diagnostic in the Rails log") },
    { id: "live-stale-client-after-redirect", rule: "WIRE-5", live: true, file: MODULE, find: RECONFIGURE,
      replace: "        config\n", examples: examples(LIVE_SPEC, "takes a redirect made after first use") },
    { id: "live-raising-lookup-on-request-path", rule: "WIRE-4", live: true, file: CONTROLLER, find: RESOLVE,
      replace: RAISING_LOOKUP,
      examples: examples(LIVE_SPEC, "serves the page in the source language when the API refuses the key") }
  ].freeze
end
