# Conformance — `langsys-ruby-rails`

| | |
|---|---|
| **SDK** | `langsys-ruby-rails` — the Rails binding over the `langsys` Ruby gem |
| **Spec revision read** | langsys2 a95af2c2…, docs/sdk-spec.mdx blob 5d7e6890b733a50fb6f5f5c30e0056c6ef7bcf45 |
| **specVersion** | 8.2.18 (113 rules) |
| **Profiles** | server, binding — derived: binding over langsys-ruby |
| **SDK revision** | `feature/838_write_key_gating` |
| **Core consumed** | `langsys-ruby` `feature/838_write_key_gating`, by path (`../langsys-ruby`); suite and both mutation passes run against `9341cc4`, a clean checkout of that commit |
| **Contract double** | `spec/contract-fixture/`, vendored byte-exact from langsys-js-typescript, git tree `542f57f5ffcb9038db1b7411152b7e31b96cb269` (the suite recomputes the tree id) |
| **Suite** | 122 hermetic examples, among them 4 against the contract double (`rake spec`) · 20 live (`rake integration`) · 33 hermetic and 11 live mutants (`rake mutation`, `rake mutation:live`) |

`delegated` rows name the core's row and carry tier `-`: the behaviour's tier lives on that row,
and the evidence here is an absence probe with a firing control proving this binding does not
take part. `n/a (pure)` marks evidence whose property does not depend on what the API answers.

## What surfaced while writing this

Every item came from executing code.

1. **The locale an app sets on I18n is invisible to a naive read inside a view.** While a view
   renders, ActionView stands an `I18nProxy` in for `I18n.config`, so the config's own record of
   an explicitly set locale reads as unset there. The binding reads the config the proxy wraps.
2. **`I18n.locale` always answers something.** With nothing set it answers the default locale, which
   would read as a choice the app never made; only the i18n config's explicitly set locale says the
   app resolved one. `I18n.with_locale` restores the resolved locale rather than clearing it, so
   an app that uses it anywhere keeps an explicit locale on that thread afterwards — which, for
   such an app, is its own choice.
3. **Rails words a failure before it fills it.** `ActiveModel::Error.generate_message` with
   interpolation skipped returns the message with the plural form Rails would choose for the
   count, placeholders intact; `full_message` writes the label in. So the template is Rails' own
   sentence and, once filled, Rails' rendered message exactly.
4. **A nested failure is worded by the record that failed.** A failure imported under a path such
   as `items[3].email` names no method on the parent; the sentence comes from the inner record
   and the label from the path, as Rails renders it.
5. **The local API throttles at 120 requests a minute per address, shared by every lane on the
   machine.** A throttled catalog fetch degrades to source text — WIRE-4 holding — which reads
   like a failed translation. The live suite paces itself to half that budget.
6. **Core additions came from this lane's wiring**: `Client#resolved_locale` for the layout helper,
   `Migration#key?` for the I18n bridge, a snapshot's locales standing in for authorization
   offline, and `Client#framework_locale` for the locale an app set.

## Rules

| Rule | Status | Tier | Evidence |
|---|---|---|---|
| GATE-1 | delegated | - | Core row: langsys-ruby GATE-1. Absence probe `spec/delegation_probe_spec.rb` › "capability decision"; firing control on the core. |
| GATE-2 | delegated | - | Core row: langsys-ruby GATE-2. Absence probe `spec/delegation_probe_spec.rb` › "queue bookkeeping"; firing control on the core. A read-only session's queue is left to the core: `spec/request_boundary_spec.rb` › "does not discard a read-only session's queue; the core decides what happens to it". |
| GATE-3 | implemented | n/a (pure) | Owned here, per the core's declared GATE-3 posture. `RequestBoundary` calls `Client#reset_write_decision!` as each request enters and after it completes. `spec/request_boundary_spec.rb` › "is dropped once the request is done, though the render recorded one" (positive control: the render saw a decision) and › "drops a decision recorded outside any request before the request can read it". Mutants `decision-kept-after-request`, `decision-kept-into-request`. Tier: an in-memory lifetime no stateful fixture can observe. |
| GATE-4 | delegated | - | Core row: langsys-ruby GATE-4. Absence probe `spec/delegation_probe_spec.rb` › "cache writes and keys"; firing control on the core. |
| GATE-5 | delegated | - | Core row: langsys-ruby GATE-5. Absence probe `spec/delegation_probe_spec.rb` › "queue bookkeeping"; firing control on the core. |
| GATE-6 | n/a (architecture: neither this binding nor langsys-ruby has a report lane (HINT-2), so registering and reporting cannot both fire; live if a report lane is added to either) | - | Absence probe `spec/delegation_probe_spec.rb` › "request construction" finds no `discovery/hint`. |
| GATE-7 | implemented | live | Both binding entry points that can detect a miss feed the core's register lane, the server profile's only lane. Live: `spec/integration/live_spec.rb` › "serves the request locale's translation in the response bytes, and the base language only for a miss" — an `ls` miss is held by the server afterwards. Hermetic: `spec/binding_conformance_spec.rb` › "Langsys::Rails.t queues a miss, once, and a hit not at all" and › "the ls helper in a rendered view queues a miss, once, and a hit not at all". Mutant `ls-feeds-no-lane`. |
| GATE-8 | delegated | - | Core row: langsys-ruby GATE-8. Absence probe `spec/delegation_probe_spec.rb` › "capability decision"; firing control on the core. |
| GATE-9 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| GATE-10 | implemented | live | Producing half: `ls` prints translated text inline, so the binding gives the layout `langsys_resolved_attributes`, which is `data-ls-resolved="<locale>"` when the render locale differs from the project's base and empty otherwise — the core's `Client#resolved_locale`, the decision its `translate_page` makes for `<html>`. Live: › "marks a page rendered in a target locale, and leaves a base-locale page unmarked". Hermetic: `spec/binding_conformance_spec.rb` › "marks nothing when the project's base locale cannot be read". Reading half: this binding has no DOM reader; `ls` is a bare `t()` call, outside the rule by construction. Mutants `root-always-marked`, `live-root-always-marked`. |
| CAT-1 | delegated | - | Core row: langsys-ruby CAT-1. Absence probe `spec/delegation_probe_spec.rb` › "catalog inspection"; firing control on the core. |
| CAT-2 | delegated | - | Core row: langsys-ruby CAT-2. Absence probe `spec/delegation_probe_spec.rb` › "catalog inspection"; firing control on the core. |
| CAT-3 | delegated | - | Core row: langsys-ruby CAT-3. Absence probe `spec/delegation_probe_spec.rb` › "catalog inspection"; firing control on the core. |
| REG-1 | delegated | - | Core row: langsys-ruby REG-1. Absence probe `spec/delegation_probe_spec.rb` › "capability decision"; firing control on the core. Live: › "pushes nothing from a read-only key, while the same render on a write key does". |
| REG-2 | delegated | - | Core row: langsys-ruby REG-2. Absence probe `spec/delegation_probe_spec.rb` › "send scheduling"; firing control on the core. |
| REG-3 | implemented | live | The request-completion flush is owned here, per the core's declared REG-3 wrapper obligation: `RequestBoundary` calls the core's public `flush_pending` once the response is sent. Live, both completion paths: › "registers a render's miss only once the server closes the body" and › "registers a render's miss only once the server runs rack.response_finished". Worker shutdown is the core's best-effort `at_exit` (`auto_flush`, off by default as in the core); `Langsys::Rails.client.flush_pending` is the manual flush. Mutants `boundary-never-flushes`, `live-flush-on-the-request-path`. |
| REG-4 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| REG-5 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| REG-6 | delegated | - | Core row: langsys-ruby REG-6. Absence probe `spec/delegation_probe_spec.rb` › "queue bookkeeping"; firing control on the core. |
| REG-7 | delegated | - | Core row: langsys-ruby REG-7. Absence probe `spec/delegation_probe_spec.rb` › "queue bookkeeping"; firing control on the core. |
| REG-8 | delegated | - | Core row: langsys-ruby REG-8. Absence probe `spec/delegation_probe_spec.rb` › "queue bookkeeping"; firing control on the core. |
| REG-9 | delegated | - | Core row: langsys-ruby REG-9. Absence probe `spec/delegation_probe_spec.rb` › "batching"; firing control on the core. |
| REG-10 | delegated | - | Core row: langsys-ruby REG-10. Absence probe `spec/delegation_probe_spec.rb` › "failure handling"; firing control on the core. |
| REG-11 | delegated | - | Core row: langsys-ruby REG-11. Absence probe `spec/delegation_probe_spec.rb` › "ellipsis handling"; firing control on the core. |
| REG-12 | delegated | - | Core row: langsys-ruby REG-12. Absence probe `spec/delegation_probe_spec.rb` › "catalog inspection"; firing control on the core. |
| REG-13 | delegated | - | Core row: langsys-ruby REG-13. Absence probe `spec/delegation_probe_spec.rb` › "catalog inspection"; firing control on the core. |
| HINT-1 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-2 | delegated | - | Core row: langsys-ruby HINT-2. Absence probe `spec/delegation_probe_spec.rb` › "request construction"; firing control on the core. |
| HINT-3 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-4 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-5 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-6 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-7 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-8 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-9 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-10 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-11 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-12 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| HINT-13 | n/a (architecture: Rails has no client-side router, and every navigation is a new request that enters the core through `ls`; live if the binding ships a client entry point) | - | No navigation hook exists to wire. |
| ICU-1 | delegated | - | Core row: langsys-ruby ICU-1. Absence probe `spec/delegation_probe_spec.rb` › "interpolation"; firing control on the core. |
| ICU-2 | delegated | - | Core row: langsys-ruby ICU-2. Absence probe `spec/delegation_probe_spec.rb` › "interpolation"; firing control on the core. |
| ICU-3 | delegated | - | Core row: langsys-ruby ICU-3. Absence probe `spec/delegation_probe_spec.rb` › "interpolation"; firing control on the core. |
| ICU-4 | delegated | - | Core row: langsys-ruby ICU-4. Absence probe `spec/delegation_probe_spec.rb` › "interpolation"; firing control on the core. |
| ICU-5 | delegated | - | Core row: langsys-ruby ICU-5. Absence probe `spec/delegation_probe_spec.rb` › "interpolation"; firing control on the core. |
| ICU-6 | delegated | - | Core row: langsys-ruby ICU-6. Absence probe `spec/delegation_probe_spec.rb` › "interpolation"; firing control on the core. |
| CID-1 | delegated | - | Core row: langsys-ruby CID-1. Absence probe `spec/delegation_probe_spec.rb` › "content-block identity"; firing control on the core. |
| CID-2 | delegated | - | Core row: langsys-ruby CID-2. Absence probe `spec/delegation_probe_spec.rb` › "content-block identity"; firing control on the core. |
| CID-3 | delegated | - | Core row: langsys-ruby CID-3. Absence probe `spec/delegation_probe_spec.rb` › "content-block identity"; firing control on the core. |
| CID-4 | delegated | - | Core row: langsys-ruby CID-4. Absence probe `spec/delegation_probe_spec.rb` › "content-block identity"; firing control on the core. |
| TOK-1 | delegated | - | Core row: langsys-ruby TOK-1. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| TOK-2 | delegated | - | Core row: langsys-ruby TOK-2. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| TOK-3 | delegated | - | Core row: langsys-ruby TOK-3. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| TOK-4 | delegated | - | Core row: langsys-ruby TOK-4. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| TOK-5 | delegated | - | Core row: langsys-ruby TOK-5. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| TOK-6 | delegated | - | Core row: langsys-ruby TOK-6. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| MARK-1 | delegated | - | Core row: langsys-ruby MARK-1. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| MARK-2 | delegated | - | Core row: langsys-ruby MARK-2. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| MARK-3 | delegated | - | Core row: langsys-ruby MARK-3. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| MARK-4 | delegated | - | Core row: langsys-ruby MARK-4. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. |
| SSR-1 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| SSR-2 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| SSR-3 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| SRV-1 | implemented | live | › "serves the request locale's translation in the response bytes, and the base language only for a miss": `ls` under `?locale=es-ES` serves the fixture's `Soporte Técnico` in the response body, and a phrase absent from the catalog serves its source text and is held by the server afterwards. Mutant `live-serves-base-language`. |
| SRV-2 | implemented | n/a (pure) | `spec/binding_conformance_spec.rb` › "serves each of two renders suspended mid-flight together only its own locale's text": a two-party rendezvous holds an es-ES and a de-DE request mid-render at once, and the meeting itself is asserted. Mutant `process-global-locale`. Tier: an isolation property no stateful fixture can observe. |
| SRV-3 | implemented | live | Collection runs after the response is sent, on both completion paths (REG-3's live examples), and each request runs inside a core request scope, so another request's flush cannot send its misses early: live › "holds a render's miss from another request's flush until its own response is sent" — B completes and flushes while A is held mid-render; the server holds B's miss (positive control) and not A's until A's response is out. A read-only key pushes nothing, with a write key on the same render as positive control: live › "pushes nothing from a read-only key, while the same render on a write key does". Order of events: `spec/request_boundary_spec.rb` › "posts nothing before the response is sent, even when the render outlasts the core's debounce window"; scope edges: › "is open for the request that builds the client", › "is released when the application raises, so its misses are not held until shutdown". Mutants `flush-on-the-request-path`, `response-finished-path-ignored`, `boundary-behind-the-executor`, `no-request-scope`, `scope-held-after-error`, `live-flush-on-the-request-path`, `live-response-finished-ignored`, `live-no-request-scope`. |
| SRV-4 | n/a (architecture: Rails views emit terminal HTML and this binding takes part in no hydration hand-off, the spec's per-SDK table row for it; live if the binding ever seeds a client-side Langsys SDK before hydration) | - | No client catalog exists to seed. |
| SRV-5 | delegated | - | Core row: langsys-ruby SRV-5. Absence probe `spec/delegation_probe_spec.rb` › "tokenizer and host identity"; firing control on the core. `ls` takes a string; subtree walks reached through `Langsys::Rails.client` are the core's. |
| SRV-6 | implemented | live | The locale the app set on I18n is the request's locale: the locale source reads it at lookup time (apps set it in callbacks that run after the binding's) and the core's `Client#framework_locale` maps and validates it — `es-ES` is `es-es`, a bare `es` the project's default Spanish locale, an unsupported one the base — and the binding adds no `Vary` and writes no cookie for it. Only where the app set none does the controller concern take the locale from the core's `resolve_request_locale` — URL parameter, then the locale cookie, then `Accept-Language`, each validated — naming what that choice depended on in `Vary` and writing the cookie only for a URL choice. Hermetic: `spec/integration_spec.rb` › "serves the app's locale whatever the URL, cookie and header say, and adds no Vary or cookie", › "maps a bare language to the project's default locale for it", › "serves the base locale for an app locale the project does not serve", › "resolves the locale itself when the app set none", and the four nothing-resolved cases. Live, against the fixture project: › "lets the URL win over a conflicting cookie and header, and adds no Vary", › "lets the cookie win over the header, with Vary: Cookie", › "negotiates the header alone, with Vary: Accept-Language", › "falls through a locale the project does not serve, and never writes it back". Mutants `app-locale-ignored`, `view-proxy-not-unwrapped`, `vary-on-app-locale`, `vary-dropped`, `cookie-written-for-any-source`, `live-vary-dropped`. |
| MSG-1 | implemented | n/a (pure) | An entry is `template`, `params` when it has markers, and `message`, plus what Rails already reports, unchanged: the attribute as `field` and the error key as `code`. `spec/messages_spec.rb` › "carries numbers as numbers, params only with markers, and message the filled template" and › "keeps Rails' own field path, and words a nested failure as Rails renders it". The binding adds no error body of its own; `Langsys::Messages.attach` is the core's, for an app that wants the entries beside its own. |
| MSG-2 | implemented | n/a (pure) | `code` is Rails' own error key, passed through; a failure that is only text carries none. › "passes the error key through unchanged" (`blank`, `too_short`, `invalid`, `less_than`, `confirmation`) and › "registers a failure that arrives as text only as that text, with no code and no params". Mutant `code-mapped`. |
| MSG-3 | implemented | n/a (pure) | The template is Rails' own sentence: ActiveModel's message for the failure with interpolation skipped — its own lookup, defaults chain and plural choice — inside its full message, so the label is written in where Rails writes it; every other interpolation is a `{name}` marker. › "yields one entry per failure, each Rails' sentence with {count} as a marker and the count as a param", › "is Rails' rendered message exactly, once filled", › "keeps the plural form Rails chose for the count", › "turns an app's own interpolation value into a marker". Mutant `values-filled-in`. |
| MSG-4 | implemented | n/a (pure) | Each marker's value is the one Rails would interpolate — a count, the failing value, an app's own key — numbers as numbers and dates as ISO dates; `message` is the filled template, and equals Rails' rendered message. › "carries numbers as numbers, params only with markers, and message the filled template", › "gives a date bound as an ISO date param". Mutant `params-kept-as-strings`. |
| MSG-5 | implemented | contract | `ls_message(entry)` is the core's `render_message`: the catalog's translation of `template`, filled from `params`, else `message`. Against the contract double, through a failed Rails form: `spec/contract_spec.rb` › "renders a translated template, filled through the catalog's ICU from a count param", › "renders a translated template with no markers", › "falls back to the entry's message where the catalog has no translation". `spec/messages_spec.rb` › "falls back to message with no translation, and never looks message up". Mutant `message-used-as-lookup-key`. |
| MSG-6 | implemented | live | Templates register under the core's messages category, `Errors` by default (`messages_category` passes through): live › "registers a template the catalog lacks under Errors, once the response is sent" asserts the server holds it under `Errors` and not under the page's category. |
| MSG-7 | implemented | live | `rake langsys:messages` (REGISTER=1 registers; STRICT=1 fails on any message it cannot list) runs the core's `Messages::Command` over the app's sources plus `Langsys::Rails::ValidatorSource`, which lists for each validator exactly the template a failure at runtime produces, and reports a custom validator, a `validate` method or block, or a message or bound built by a proc — each with what would make it listable (`langsys_message_templates`). Live: › "registers every listed template on the first run, and nothing on the second". Hermetic: › "lists, for each validator, exactly the template a failure at runtime produces", › "reports a custom rule it cannot list, exiting zero, and non-zero under strict", › "lists a custom rule's declared templates". Mutant `custom-rule-not-reported`. |
| MSG-8 | implemented | live | Every entry goes through the core's `emit_message`, which registers a template the catalog lacks on the post-response flush. Live: › "registers a template the catalog lacks under Errors, once the response is sent" (absent before the body closes, held after) and › "registers nothing from a read-only key, while the same failure on a write key does". Mutant `live-template-never-registered`. |
| MSG-9 | implemented | n/a (pure) | Entries come from the failure Rails reports — its error key and options — worded by ActiveModel with interpolation skipped, never from parsing rendered text; a failure that is only text registers as that text with no params. › "yields one entry per failure, each Rails' sentence with {count} as a marker and the count as a param", › "registers a failure that arrives as text only as that text, with no code and no params". Mutant `entries-from-rendered-text`. |
| MSG-10 | implemented | n/a (pure) | The label is the one Rails prints — `human_attribute_name`, declared or derived — written in by ActiveModel's own full message. › "writes the declared label in, one template per label", › "uses the name Rails derives where no label is declared", › "writes the confirmed field's label into a mismatch, as Rails does"; the listing names a validated field with no declared label as advice, never failing: › "names a validated field with no declared label as advice, never failing, even under strict". Mutants `label-guessed-from-key`, `unlabelled-field-not-advised`. |
| MSG-11 | implemented | n/a (pure) | Rails' label placeholders, `%{attribute}` and `%{model}`, are written in; every other interpolation is a value marker. A declared template goes through the core's `TemplateCatalog#add`, which refuses one still holding Rails' label placeholders: › "refuses a declared template still holding Rails' label placeholder". The fill-time warning is the core's `emit_message`. Mutant `declared-template-unchecked`. |
| MSG-12 | n/a (architecture: a failed Rails form re-renders in the same response (`render :new, status: :unprocessable_content`), so no redirect exists for entries to cross; live if the binding adds a flash or Inertia hand-off) | - | A failed request renders its entries in its own response. |
| MIG-1 | implemented | n/a (pure) | The I18n bridge is installed only when `config.langsys.migration` names source files, and `migration` passes to the core unchanged. `spec/i18n_bridge_spec.rb` › "leaves I18n alone, and consults no migration file, when the mode is unset". Mutant `bridge-installed-unconditionally`. |
| MIG-2 | implemented | n/a (pure) | `Langsys::Rails::I18nBridge` answers `I18n.t`, and the `t` view helper once ActionView has resolved a lazy key: a key in the migration files (the core's `Migration#key?`) or a literal string no backend knows goes to the core's `translate_legacy` with `entry_point: :rails`; Rails' own keys and scoped or defaulted lookups go to the backend it wraps. › "answers a key in the source file with its value's phrase, under the key's namespace, never the key", › "converts a key's Rails plural to one ICU phrase", › "treats a literal string as source text, converting the %{name} placeholders it passes", › "leaves Rails' own keys, and scoped or defaulted lookups, to the I18n backend". Mutants `no-literal-miss`, `rails-keys-hijacked`. |
| MIG-3 | delegated | - | Core row: langsys-ruby MIG-3. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-4 | delegated | - | Core row: langsys-ruby MIG-4. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-5 | delegated | - | Core row: langsys-ruby MIG-5. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-6 | delegated | - | Core row: langsys-ruby MIG-6. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-7 | delegated | - | Core row: langsys-ruby MIG-7. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-8 | implemented | n/a (pure) | The bridge is the Rails entry point of the one contract, reading the core's file configuration, per ecosystem as 8.2.15 words the test: › "gives a plural key through I18n.t the same phrase and category as the core, from a rails-i18n file" and › "gives a key through I18n.t the same phrase and category as the base SDK's translate_legacy". Agreement across ecosystems is the `same_phrase_as` rows of `mig-vectors.json`, which the core executes. Mutant `bridge-overrides-category`. |
| MIG-9 | delegated | - | Core row: langsys-ruby MIG-9. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| SNAP-1 | delegated | - | Core row: langsys-ruby SNAP-1. Absence probe `spec/delegation_probe_spec.rb` › "snapshot export and integrity"; firing control on the core. |
| SNAP-2 | implemented | live | `config.langsys.snapshot` names a snapshot file, passed unchanged to the core's `Client.new(snapshot:)`; the Railtie builds the client at boot when one is configured, so the catalog is seeded before the first request and a snapshot the core refuses fails the boot. Live, with the API unreachable: `spec/integration/live_spec.rb` › "renders a first request from the snapshot with the API unreachable" — a full Rails request to `?locale=es-ES` serves the snapshot's translation, the locale validated against the snapshot's own locales. Live › "fetches the live catalog for a phrase the snapshot lacks, and decides that miss against it" — the miss is held by the server afterwards. Hermetic: `spec/snapshot_spec.rb` › "renders the first request from the snapshot, with no catalog fetch", › "builds the client at boot when a snapshot is configured, and not otherwise", › "fails the boot, naming the reason, when the snapshot was edited". Mutants `snapshot-not-seeded-at-boot`, `snapshot-not-passed`, `live-snapshot-not-passed`. |
| SNAP-3 | delegated | - | Core row: langsys-ruby SNAP-3. Absence probe `spec/delegation_probe_spec.rb` › "snapshot export and integrity"; firing control on the core. |
| BIND-1 | implemented | n/a (pure) | `spec/binding_conformance_spec.rb` › "renders and queues exactly what calling the core directly does" (eight vectors, output and resulting queue compared with `Langsys::Client#translate`) and › "makes the ls helper the same call as Langsys::Rails.t". Timing adaptations are the request boundary (GATE-3, REG-3, SRV-3); shape adaptations are the controller's request-to-locale plumbing (SRV-6), the error normalizer (MSG-9) and the I18n bridge (MIG-2). Mutant `t-adapts-meaning`. |
| BIND-2 | implemented | n/a (pure) | Absence probe `spec/delegation_probe_spec.rb` › "capability decision" finds no capability value in lib/; firing control: core. `spec/request_boundary_spec.rb` › "does not discard a read-only session's queue; the core decides what happens to it". Mutant `boundary-branches-on-capability`. |
| BIND-3 | implemented | n/a (pure) | Absence probe `spec/delegation_probe_spec.rb` › "request construction", "send scheduling" and "batching" find nothing in lib/; firing controls: core. Calling the core's `flush_pending` when a request completes is lifecycle timing, which BIND-1 permits and the core's CONFORMANCE assigns to this wrapper. |
| BIND-4 | implemented | n/a (pure) | Every setting is a core client keyword passed unchanged, or SRV-6's wiring (`query_param`, `cookie_name`, `cookie_max_age`), which BIND-4 names as allowed: › "names every core setting by the core client's own keyword", › "hands each configured core setting to the core client unchanged", › "gives auto_flush the core's meaning and the core's default", › "adds only SRV-6's wiring: where the URL parameter and the locale cookie live", › "accepts only declared settings, and the Railtie reads exactly those". Mutants `binding-only-setting`, `auto-flush-default-diverges`, `core-setting-dropped`. |
| BIND-5 | implemented | n/a (pure) | › "shows a changed catalog on the very next call" and › "memoizes nothing but its own configuration objects". Mutant `lookup-results-memoized`. |
| BIND-6 | implemented | n/a (pure) | › "exposes the core client by reference plus framework idioms, and no behaviour of its own": `configure`, `config`, `client`, `client=`, `reset_client!`, `t`, `locale`, and the helpers `ls`, `ls_message`, `langsys_resolved_attributes`, each a hook over a core value; `client` is the core's `Langsys::Client`. Mutant `new-behaviour-name`. |
| GRANT-1 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| GRANT-2 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| GRANT-3 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| GRANT-4 | n/a (profile: browser) | - | Profiles: browser. This binding runs in a server process. |
| CACHE-1 | delegated | - | Core row: langsys-ruby CACHE-1. Absence probe `spec/delegation_probe_spec.rb` › "cache writes and keys"; firing control on the core. |
| CACHE-2 | delegated | - | Core row: langsys-ruby CACHE-2. Absence probe `spec/delegation_probe_spec.rb` › "failed-fetch memory"; firing control on the core. |
| OBS-1 | implemented | live | The binding's half: the core's diagnostic reaches the host's log. The client is built with `logger:`, defaulting to `Rails.logger`. Live › "puts the core's unusable-capability diagnostic in the Rails log, once across requests" (read key, three requests, one line), with › "logs no such diagnostic on a write key (control)". Mutants `logger-not-passed`, `live-logger-not-passed`. |
| WIRE-1 | delegated | - | Core row: langsys-ruby WIRE-1. Absence probe `spec/delegation_probe_spec.rb` › "request construction"; firing control on the core. |
| WIRE-2 | delegated | - | Core row: langsys-ruby WIRE-2. Absence probe `spec/delegation_probe_spec.rb` › "request construction"; firing control on the core. |
| WIRE-3 | delegated | - | Core row: langsys-ruby WIRE-3. Absence probe `spec/delegation_probe_spec.rb` › "request construction"; firing control on the core. The cookie holds the core's canonical lowercase locale from `resolve_request_locale`. |
| WIRE-4 | implemented | live | Binding code sits on every request path — locale resolution and the request boundary. Live › "serves the page in the source language when the API refuses the key, and records nothing". Hermetic › "serves the source language and records nothing" (connection refused) and `spec/request_boundary_spec.rb` › "neither builds a client nor raises for a request that never translated". Mutants `raising-lookup-on-request-path`, `live-raising-lookup-on-request-path`, `boundary-builds-a-client`. |
| WIRE-5 | implemented | live | `api_url` passes to the core and is documented in the README. Live › "takes a redirect made after first use: a dead address degrades, then the live one translates"; reconfiguring rebuilds the client. The contract suite runs entirely through the same seam. Mutants `stale-client-after-redirect`, `live-stale-client-after-redirect`. |
| CONF-1 | implemented | n/a (pure) | Every row graded `live` asserts on the served bytes or on server state read back through a separate, uncached client; `contract` rows read the double's state. Every-path clause: REG-3 and SRV-3 on both completion paths, GATE-7 on both entry points, MSG-5 through a rendered form. WebMock-backed examples carry no `live` or `contract` grade. |
| CONF-2 | implemented | n/a (pure) | Every row carries a canonical tier. `spec/conformance_doc_spec.rb` checks the header rows, one status table, all 113 ids once each in spec order, the status and tier vocabulary and the tiers each status permits, and a summary computed from the table. The contract double is vendored byte-exact at tree 542f57f5 and re-derived by the suite. Mutant `summary-drifts-from-table`. |
| CONF-3 | implemented | n/a (pure) | `spec/mutation/manifest.rb`, run by `rake mutation` (33 hermetic mutants) and `rake mutation:live` (11 live). An entry must apply exactly once; its examples must be green, with none pending, before the edit, and red without a load error after it; the file is then restored byte for byte. Result on this tree: 33/33 hermetic and 11/11 live mutants killed. |

## Summary

Computed from the table above; `spec/conformance_doc_spec.rb` fails the build when they disagree.

| Status | Count |
|---|---|
| implemented | 35 |
| delegated | 53 |
| n/a (profile: browser) | 21 |
| n/a (architecture) | 4 |
| total | 113 |

## Obligations taken over from `langsys-ruby`

The core's CONFORMANCE.md names this repo as the owner of what its process-wide client cannot do
for itself. `Langsys::Rails::RequestBoundary`, which the Railtie inserts in front of
`ActionDispatch::Executor`, carries them:

- **GATE-3** — `Client#reset_write_decision!` as a request enters and once it completes.
- **REG-3 / SRV-3** — `Client#flush_pending` once the response has been sent, on whichever
  completion path the server provides, inside a core request scope
  (`Langsys.begin_request_scope` / `Langsys.end_request_scope`).

The core's MSG-9, MSG-10, MSG-12 and MIG-8 rows name a framework binding as where those rules are
live: here, `Langsys::Rails::Messages`, `Langsys::Rails::ValidatorSource` and
`Langsys::Rails::I18nBridge`.

## Gaps, ranked by cost

1. **MIG-9, the one-time import of existing translations** (delegated; the core row is not
   implemented until the 907 merge lands the endpoint's `translations` map). A migrating app's
   existing translations are machine-translated again rather than kept. Translation spend, and
   work already done lost to reviewers.
2. **Label casing is the framework's.** `human_attribute_name` is written into the sentence as
   the app declares it, so an app that capitalises labels gets `The Email is required.`. Cosmetic,
   and fixed in the app's locale file.
3. **Listing both size wordings for an untyped attribute** registers one template that may never
   be emitted. Catalog noise, no runtime cost.

## Release wave

- **The base gem is unpublished.** `Gemfile` points `langsys` at `../langsys-ruby` for
  co-development. At publication: publish `langsys` first, delete that line (the gemspec requires
  `langsys >= 0.1.0`), then publish this gem.
- **`Gemfile.lock` is gitignored.** The suite is measured under the lock resolved with this
  branch; adding `activemodel` changed no other gem's version.

## Provenance

The commands, not the values, are the record:

```
# The spec blob and rule ids this file rows against
git -C ../langsys2 rev-parse a95af2c2:docs/sdk-spec.mdx
#   -> 5d7e6890b733a50fb6f5f5c30e0056c6ef7bcf45
git -C ../langsys2 cat-file blob 5d7e6890 | grep -cE '^### [A-Z]+-[0-9]+ '
#   -> 113

# Hermetic suite (includes the contract double), lint, signatures, hermetic mutants
bundle exec rake spec && bundle exec rubocop && bundle exec rake rbs && bundle exec rake mutation

# Live suite and live mutants — fixture: langsys2 SdkIntegrationSeeder, slot 13 (local only)
LANGSYS_API_URL=http://langsys2.test/api \
LANGSYS_PROJECT_ID=c0de0000-5d10-4000-8000-000000000013 \
LANGSYS_API_KEY=sdk_integration_rails_local_only_do_not_deploy \
LANGSYS_READ_KEY=sdk_integration_rails_read_local_only_do_not_deploy \
  bundle exec rake integration mutation:live
```

## Limitations

- Rows are claims about `feature/838_write_key_gating`, not about `main`.
- Live evidence runs against the local stack on this repo's own fixture project, where
  registration is synchronous; nothing downstream of registration is asserted.
- `delegated` rows name the core's row, not its grade; the program's checker resolves each
  against langsys-ruby's current CONFORMANCE.md.
- The WebMock-backed examples are hermetic twins of the live and contract ones and grade nothing
  that depends on what the API answers.
