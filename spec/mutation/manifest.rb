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
  RESOLVER = "lib/langsys/rails/locale_resolver.rb"

  BOUNDARY_SPEC = "spec/request_boundary_spec.rb"
  BINDING_SPEC = "spec/binding_conformance_spec.rb"
  PROBE_SPEC = "spec/delegation_probe_spec.rb"
  LIVE_SPEC = "spec/integration/live_spec.rb"
  DOC_SPEC = "spec/conformance_doc_spec.rb"

  T_CALL = "        client.translate(phrase, category: category, params: params.empty? ? nil : params)\n"
  FLUSH = "          client.flush_pending\n"
  BODY_PROXY = "        [status, headers, ::Rack::BodyProxy.new(body) { complete }]\n"
  FINISHED = "        if (finished = env[\"rack.response_finished\"])\n"
  LOGGER_FALLBACK = "        options[:logger] ||= rails_logger\n"
  RECONFIGURE = "        reset_client!\n        config\n"
  RESOLVE = "      def resolve(query:, cookie:, accept_language:, client:)\n"
  RAISING_LOOKUP = "#{RESOLVE}        client.get_translations(use_cache: false) || " \
                   "raise(Langsys::Error, \"catalog unavailable\")\n".freeze
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
      replace: "        complete\n        [status, headers, body]\n",
      examples: examples(BOUNDARY_SPEC, "on the body-close path", "posts nothing before the response is sent") },
    { id: "response-finished-path-ignored", rule: "SRV-3", file: BOUNDARY, find: FINISHED,
      replace: "        if (finished = nil)\n",
      examples: examples(BOUNDARY_SPEC, "on the rack.response_finished path") },
    { id: "boundary-behind-the-executor", rule: "SRV-3", file: RAILTIE,
      find: "config.app_middleware.insert_before ActionDispatch::Executor, RequestBoundary",
      replace: "config.app_middleware.insert_after ActionDispatch::Executor, RequestBoundary",
      examples: examples(BOUNDARY_SPEC, "sits in front of ActionDispatch::Executor",
                         "only after Rails has completed the request") },
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
      find: "LOCALE_SETTINGS = %i[supported query_param cookie_name cookie_max_age].freeze",
      replace: "LOCALE_SETTINGS = %i[supported query_param cookie_name cookie_max_age discovery].freeze",
      examples: examples(BINDING_SPEC, "introduces exactly three settings") },
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
    { id: "raising-lookup-on-request-path", rule: "WIRE-4", file: RESOLVER, find: RESOLVE,
      replace: RAISING_LOOKUP,
      examples: examples(BINDING_SPEC, "serves the source language and records nothing") },

    # -- the conformance document --------------------------------------------------------
    { id: "summary-drifts-from-table", rule: "CONF-2", file: "CONFORMANCE.md",
      find: "| implemented | 16 |", replace: "| implemented | 17 |",
      examples: examples(DOC_SPEC, "has a summary computed from the table") },

    # -- live: the same breaks, observed against the real server ---------------------------
    { id: "live-flush-on-the-request-path", rule: "SRV-3", live: true, file: BOUNDARY, find: BODY_PROXY,
      replace: "        complete\n        [status, headers, body]\n",
      examples: examples(LIVE_SPEC, "registers a render's miss only once the server closes the body") },
    { id: "live-response-finished-ignored", rule: "SRV-3", live: true, file: BOUNDARY, find: FINISHED,
      replace: "        if (finished = nil)\n",
      examples: examples(LIVE_SPEC, "registers a render's miss only once the server runs rack.response_finished") },
    { id: "live-serves-base-language", rule: "SRV-1", live: true, file: MODULE, find: T_CALL,
      replace: "        client.translate(phrase, category: category, params: params.empty? ? nil : params, " \
               "locale: config.base_locale)\n",
      examples: examples(LIVE_SPEC, "serves the request locale's translation in the response bytes") },
    { id: "live-logger-not-passed", rule: "OBS-1", live: true, file: MODULE, find: LOGGER_FALLBACK, replace: "",
      examples: examples(LIVE_SPEC, "puts the core's unusable-capability diagnostic in the Rails log") },
    { id: "live-stale-client-after-redirect", rule: "WIRE-5", live: true, file: MODULE, find: RECONFIGURE,
      replace: "        config\n", examples: examples(LIVE_SPEC, "takes a redirect made after first use") },
    { id: "live-raising-lookup-on-request-path", rule: "WIRE-4", live: true, file: RESOLVER, find: RESOLVE,
      replace: RAISING_LOOKUP,
      examples: examples(LIVE_SPEC, "serves the page in the source language when the API refuses the key") }
  ].freeze
end
