# Conformance — `langsys-ruby-rails`

| | |
|---|---|
| **SDK** | `langsys-ruby-rails` — the Rails binding over the `langsys` Ruby gem |
| **Spec revision read** | langsys2 cd5468c7…, docs/sdk-spec.mdx blob abe122cf5346f92a0474b627d49451e6de9cd761 |
| **specVersion** | 8.2.13 (113 rules) |
| **Profiles** | server, binding — the spec's per-SDK table row for `langsys-ruby-rails`, over core `langsys-ruby` |
| **SDK revision** | `feature/838_write_key_gating` |
| **Core consumed** | `langsys-ruby` `feature/838_write_key_gating`, by path (`../langsys-ruby`); suite and both mutation passes run against `0344155`, a clean checkout of that commit |
| **Contract double** | `spec/contract-fixture/`, vendored byte-exact from langsys-js-typescript, git tree `542f57f5ffcb9038db1b7411152b7e31b96cb269` (the suite recomputes the tree id) |
| **Suite** | 113 hermetic examples, among them 4 against the contract double (`rake spec`) · 18 live (`rake integration`) · 38 hermetic and 10 live mutants (`rake mutation`, `rake mutation:live`) |

`delegated` rows name the core's row and carry tier `-`: the behaviour's tier lives on that row,
and the evidence here is an absence probe with a firing control proving this binding does not
take part. `n/a (pure)` marks evidence whose property does not depend on what the API answers.

## What surfaced while writing this

Every item came from executing code.

1. **The local API throttles at 120 requests a minute per address, shared by every lane on the
   machine.** A throttled catalog fetch degrades to source text — WIRE-4 holding — which reads
   exactly like a failed translation. The live suite paces itself to half that budget, and its
   verifier control names throttling when the catalog is unavailable.
2. **A validator's declaration does not always say what a length rule measures.** For an untyped
   or JSON attribute the listing cannot know text from a list, so it lists both wordings; the one
   emitted at runtime is chosen from the value.
3. **A confirmation failure sits on one field and names another.** Rails records it on
   `password_confirmation` and passes the confirmed field's label as `:attribute`; the entry keeps
   the failing field and writes the confirmed field's label into the sentence.
4. **A nested error attribute is not a method.** `items[3].label` cannot be read from the record;
   the size code then falls back to text, and the field is written `items.3.label`.
5. **Two core additions came from this lane's wiring.** The layout helper's decision is the core's
   `Client#resolved_locale`, so a binding does not re-derive "differs from the base locale"; and
   the I18n bridge asks `Migration#key?`, which answers without logging, because every Rails
   internal lookup passes through the bridge and falls through.
6. **ActiveModel is a runtime dependency.** The normalizer and the listing read ActiveModel's
   errors and validators; every Rails app carries the gem.

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
| SRV-6 | implemented | live | The controller concern takes the request locale from the core's `Client#resolve_request_locale` — the URL parameter, then the locale cookie, then `Accept-Language`, each validated against the project's base and target locales from authorization — adds the returned names to `Vary`, merging with any the app set, and writes the cookie only for a URL choice. Live, one URL and four requests against the fixture project: › "lets the URL win over a conflicting cookie and header, and adds no Vary", › "lets the cookie win over the header, with Vary: Cookie", › "negotiates the header alone, with Vary: Accept-Language", › "falls through a locale the project does not serve, and never writes it back". Hermetic twins in `spec/integration_spec.rb`, plus › "never serves or persists an unsupported URL locale" and › "keeps a Vary the application set, adding only what is missing". Mutants `vary-dropped`, `cookie-written-for-any-source`, `live-vary-dropped`. |
| MSG-1 | implemented | n/a (pure) | Entries are built by the core's `Messages.entry` through `emit_message`, so each carries only `field`, `code`, `message`, `template` and `params`: `spec/messages_spec.rb` › "carries only the fixed keys, numbers as numbers, and params only when there are markers" and › "writes a nested attribute as a dotted path, and a whole-record failure with no field". The envelope is the app's: `Langsys::Messages.envelope` is the core's default, reached by reference. |
| MSG-2 | implemented | n/a (pure) | The wording table in `lib/langsys/rails/messages.rb` maps each ActiveModel error type to a vocabulary code: the reference's (langsys4 `RuleWording`) where it has the rule, MSG-2's table at blob abe122cf for an exclusive upper bound (`less_than`), and the reference's `min`/`max` for inclusive bounds. › "uses MSG-2's wording for an exclusive upper bound, and min for an inclusive lower one", › "picks the size code by type: text too_short, numbers too_small, lists too_many", › "draws every code from the vocabulary", › "gives a date bound the date wording, with the date as a non-translatable param". Mutants `exclusive-bound-worded-as-max`, `size-code-ignores-type`. |
| MSG-3 | implemented | n/a (pure) | Templates are whole sentences with the label written in: › "writes human_attribute_name into the sentence, so each label is its own phrase" and › "names the confirmed field, not the confirmation field, in a mismatch". |
| MSG-4 | implemented | n/a (pure) | Only counts and dates are markers; numbers stay numbers and `message` is the filled template: › "carries only the fixed keys, numbers as numbers, and params only when there are markers". Mutant `params-kept-as-strings`. |
| MSG-5 | implemented | contract | `ls_message(entry)` is the core's `render_message`: the catalog's translation of `template`, filled from `params`, else `message`. Against the contract double, through a failed Rails form: `spec/contract_spec.rb` › "renders a translated template, filled through the catalog's ICU from a count param", › "renders a translated template with no markers", › "falls back to the entry's message where the catalog has no translation". `spec/messages_spec.rb` › "falls back to message with no translation, and never looks message up". Mutant `message-used-as-lookup-key`. |
| MSG-6 | implemented | live | Templates register under the core's messages category, `Errors` by default (`messages_category` passes through): live › "registers a template the catalog lacks under Errors, once the response is sent" asserts the server holds it under `Errors` and not under the page's category. |
| MSG-7 | implemented | live | `rake langsys:messages` (REGISTER=1 registers) runs the core's `Messages::Command` over the app's sources plus `Langsys::Rails::ValidatorSource`, which lists every template an ActiveModel class's validators can emit and reports, through `TemplateCatalog#problem`, each validated field with no label and each custom rule without declared templates (`langsys_message_templates`). Live: › "registers every listed template on the first run, and nothing on the second". Hermetic: › "lists every template a model's validators can emit, with zero problems", › "exits non-zero naming a custom rule whose templates are not declared, with the fix", › "lists a custom rule's declared templates". Mutants `unlabelled-field-not-reported`, `custom-rule-not-reported`. |
| MSG-8 | implemented | live | Every entry goes through the core's `emit_message`, which registers a template the catalog lacks on the post-response flush. Live: › "registers a template the catalog lacks under Errors, once the response is sent" (absent before the body closes, held after) and › "registers nothing from a read-only key, while the same failure on a write key does". Mutant `live-template-never-registered`. |
| MSG-9 | implemented | n/a (pure) | Entries come from `errors.details` — the failed rule and its options — never from rendered text: › "yields one entry per failed rule on a field, with the codes and params of those rules" (length and format on one field, two entries), › "never takes a template from the message Rails rendered", › "turns a failure that arrives with text only into code invalid, its sentence the template". Mutant `entries-from-rendered-text`. |
| MSG-10 | implemented | n/a (pure) | The label is `human_attribute_name`: › "writes human_attribute_name into the sentence, so each label is its own phrase"; a validated field with no declared label is named by the listing: › "names a validated field with no declared label rather than guessing one from its key". Mutants `label-guessed-from-key`, `unlabelled-field-not-reported`. |
| MSG-11 | implemented | n/a (pure) | The binding's templates carry only count and date markers. A declared template goes through the core's `TemplateCatalog#add`, which refuses label markers and framework placeholders: › "refuses a declared template carrying a label marker or a framework placeholder". The fill-time warning is the core's `emit_message`. Mutant `declared-template-unchecked`. |
| MSG-12 | n/a (architecture: a failed Rails form re-renders in the same response (`render :new, status: :unprocessable_content`), so no redirect exists for entries to cross; live if the binding adds a flash or Inertia hand-off) | - | A failed request renders its entries in its own response. |
| MIG-1 | implemented | n/a (pure) | The I18n bridge is installed only when `config.langsys.migration` names source files, and `migration` passes to the core unchanged. `spec/i18n_bridge_spec.rb` › "leaves I18n alone, and consults no migration file, when the mode is unset". Mutant `bridge-installed-unconditionally`. |
| MIG-2 | implemented | n/a (pure) | `Langsys::Rails::I18nBridge` answers `I18n.t`, and the `t` view helper once ActionView has resolved a lazy key: a key in the migration files (the core's `Migration#key?`) or a literal string no backend knows goes to the core's `translate_legacy` with `entry_point: :rails`; Rails' own keys and scoped or defaulted lookups go to the backend it wraps. › "answers a key in the source file with its value's phrase, under the key's namespace, never the key", › "converts a key's Rails plural to one ICU phrase", › "treats a literal string as source text, converting the %{name} placeholders it passes", › "leaves Rails' own keys, and scoped or defaulted lookups, to the I18n backend". Mutants `no-literal-miss`, `rails-keys-hijacked`. |
| MIG-3 | delegated | - | Core row: langsys-ruby MIG-3. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-4 | delegated | - | Core row: langsys-ruby MIG-4. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-5 | delegated | - | Core row: langsys-ruby MIG-5. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-6 | delegated | - | Core row: langsys-ruby MIG-6. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-7 | delegated | - | Core row: langsys-ruby MIG-7. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| MIG-8 | implemented | n/a (pure) | The bridge is the Rails entry point of the one contract, reading the core's file configuration: › "gives a key through I18n.t the same phrase and category as the base SDK's translate_legacy". Mutant `bridge-overrides-category`. |
| MIG-9 | delegated | - | Core row: langsys-ruby MIG-9. Absence probe `spec/delegation_probe_spec.rb` › "legacy conversion and import"; firing control on the core. |
| SNAP-1 | delegated | - | Core row: langsys-ruby SNAP-1. Absence probe `spec/delegation_probe_spec.rb` › "snapshots"; firing control on the core. |
| SNAP-2 | n/a (architecture: a Rails response is rendered on the server per request, and this binding seeds no client before a first render; live if it adds a preload hook) | - | The core's catalog cache is what a server render reads. |
| SNAP-3 | delegated | - | Core row: langsys-ruby SNAP-3. Absence probe `spec/delegation_probe_spec.rb` › "snapshots"; firing control on the core. |
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
| CONF-3 | implemented | n/a (pure) | `spec/mutation/manifest.rb`, run by `rake mutation` (38 hermetic mutants) and `rake mutation:live` (10 live). An entry must apply exactly once; its examples must be green, with none pending, before the edit, and red without a load error after it; the file is then restored byte for byte. Result on this tree: 38/38 hermetic and 10/10 live mutants killed. |

## Summary

Computed from the table above; `spec/conformance_doc_spec.rb` fails the build when they disagree.

| Status | Count |
|---|---|
| implemented | 34 |
| delegated | 53 |
| n/a (profile: browser) | 21 |
| n/a (architecture) | 5 |
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
git -C ../langsys2 rev-parse cd5468c765c67764a0e08c434d41413ead3678dc:docs/sdk-spec.mdx
#   -> abe122cf5346f92a0474b627d49451e6de9cd761
git -C ../langsys2 cat-file blob abe122cf | grep -cE '^### [A-Z]+-[0-9]+ '
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
