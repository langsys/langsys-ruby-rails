# Conformance — `langsys-ruby-rails`

| | |
|---|---|
| **SDK** | `langsys-ruby-rails` — Rails binding over the `langsys` Ruby gem |
| **Spec revision read** | langsys2 5cff03a1…, docs/sdk-spec.mdx blob 5c5c0723f88fb8e6b13f58876c7adca8b6b35691 |
| **specVersion** | 8.0.1 (79 rules) |
| **Profiles** | server, binding, all — derived: binding over langsys-ruby |
| **SDK revision** | `feature/838_write_key_gating`, cut from `main` `2751820` |
| **Core consumed** | `langsys-ruby` `feature/838_write_key_gating`, by path (`../langsys-ruby`); suite and both mutation passes last run against `9b68659`, a clean checkout of that commit |
| **Suite** | 75 hermetic examples (`rake spec`) · 10 live (`rake integration`) · 22 hermetic and 7 live mutants (`rake mutation`, `rake mutation:live`) |

**On the Profiles row.** The spec's Profiles table never names Rails, or any server framework
binding. The row is derived: a binding "inherits its core's profile and adds nothing of its own",
and `langsys-ruby` is `server` + `all`, so this repo is `server` + `binding` + `all`, and only
`browser` rules fall away on profile. The gap in the table is flagged to the operator.

## What surfaced while writing this

Every item below came from executing code — most of it measured red against `2751820` before the
fix — not from reading it.

1. **The capability branch did more damage than BIND-2 describes.** At `2751820`
   `handle_pending` flushed a writable session and *cleared* every other one. On a read-only
   session the `ls` path therefore fed neither lane: the core retains the queue (GATE-2) and warns
   once (OBS-1), and the binding threw both away after every request. GATE-7's own failure, caused
   by BIND-2's violation — measured red-first by the GATE-7 examples.
2. **Findings 3 and 4 were measured live before being fixed.** With no `logger:` passed, a
   read-only deployment put no line in the log over three requests. With the `after_action`
   flush, the fixture server already held a render's miss before the response body was closed, on
   both the body-close and `rack.response_finished` paths.
3. **Ordering within one request was not enough for SRV-3.** The core's own timer cannot post
   early — `flush_if_due` is defined and nothing calls it — measured through a render held past
   the 0.4s debounce. But the discovery queue is process-wide, so with request A held mid-render
   while request B completed, B's post-response flush sent A's miss before A's response was out.
   The binding may not schedule around that (BIND-3); the core now holds a miss recorded inside a
   request scope from every flush until that scope ends, and `RequestBoundary` opens one scope per
   request. The scope is module-level, so it is open even for the request that builds the client.
4. **A core defect reached every `ls` without params.** `Client#interpolate` skipped recovery
   when params were empty, so `ls "Welcome"` with a translation selecting on `gender` rendered the
   raw ICU source to the visitor — the spec's own motivating case. Found through the BIND-1
   equivalence vectors, routed to the Ruby lane, fixed there with red-first examples on the `t()`
   path.
5. **Locale negotiation sends no `Vary`.** Absent on all three negotiated shapes. Rails' default
   `Cache-Control: max-age=0, private, must-revalidate` keeps shared caches out, so nothing is
   cross-served by default; with `expires_in 1.hour, public: true` one URL served `Guardar` or
   `Save` by `Accept-Language` or cookie, under `Cache-Control: public`. That is the CDN cross-serve,
   reproduced. Recorded under BIND-4; the behaviour is unchanged pending the ambient-locale ruling.
6. **`?locale=` is accepted unvalidated and kept for a year.** `?locale=<script>` and
   `?locale=zz-zz` each answered 200 in source text with a one-year `Set-Cookie`; three later
   cookie-only requests each issued a catalog fetch for that locale (four over four requests),
   because a failed fetch is not cached. A crafted link pins a browser to a failed API round trip
   on every request for a year. Also pending the ambient-locale ruling.
7. **A request-boundary hook must not build the client.** The core raises `ConfigurationError`
   without credentials, so a middleware that built the client would turn every route of an
   unconfigured app into a 500 — health checks and mounted Rack apps included. The boundary
   touches only a client that already exists (WIRE-4 row).
8. **Where the flush sits changes what it holds.** Inside `ActionDispatch::Executor`, a
   post-response flush would run while Rails still holds the request's state — database
   connections, `CurrentAttributes` — across a network call. In front of it, on both completion
   paths, the flush runs after the executor completes; asserted by observing `CurrentAttributes`
   already cleared when the flush runs.

## Rules

Statuses and tiers are the conformance program's canonical set. `delegated` rows name the core's
row and carry tier `-`: the behaviour's tier lives on that row, and the evidence here is an absence
probe with a firing control proving this binding does not take part. `n/a (pure)` marks evidence
whose property does not depend on what the API answers.

| Rule | Status | Tier | Evidence |
|---|---|---|---|
| GATE-1 | delegated | - | Core row: langsys-ruby GATE-1. Absence probe `spec/delegation_probe_spec.rb` › "capability decision": lib/ never names `can_write?`, `write_enabled`, `write_signal` or `key_type`; firing control: the same pattern finds the core's gate. |
| GATE-2 | delegated | - | Core row: langsys-ruby GATE-2. Absence probe › "queue bookkeeping". The interference this binding had is gone: at `2751820` it discarded a read-only session's queue after every request; `spec/request_boundary_spec.rb` › "does not discard a read-only session's queue; the core decides what happens to it". |
| GATE-3 | implemented | n/a (pure) | Owned here, per the core's declared GATE-3 posture. `RequestBoundary` drops the core's decision (`Client#reset_write_decision!`) as each request enters and after it completes. `spec/request_boundary_spec.rb` › "is dropped once the request is done, though the render recorded one" (positive control: the render saw `true`) and › "drops a decision recorded outside any request before the request can read it". Mutants `decision-kept-after-request`, `decision-kept-into-request`. Tier: an in-memory lifetime no stateful fixture could observe. |
| GATE-4 | delegated | - | Core row: langsys-ruby GATE-4. Absence probe › "cache writes and keys": lib/ writes nothing to a cache; `cache` is handed to the core as configured. |
| GATE-5 | delegated | - | Core row: langsys-ruby GATE-5. Absence probe › "queue bookkeeping": lib/ writes and reads no registered-items marker. |
| GATE-6 | n/a (architecture: neither this binding nor langsys-ruby has a report lane (HINT-2), so registering and reporting cannot both fire; live if a report lane is ever added to either) | - | Absence probe › "request construction" finds no `discovery/hint` in lib/; firing control: the core's request construction. |
| GATE-7 | implemented | n/a (pure) | Both binding entry points that can detect a miss feed the core's register lane, the server profile's only lane: `spec/binding_conformance_spec.rb` › "Langsys::Rails.t queues a miss, once, and a hit not at all" and › "the ls helper in a rendered view queues a miss, once, and a hit not at all". Red-first: at `2751820` the `ls` path fed neither lane. Mutant `ls-feeds-no-lane`. Paths reached by reference through `Langsys::Rails.client` are the core's GATE-7. |
| GATE-8 | delegated | - | Core row: langsys-ruby GATE-8. Absence probe › "capability decision". |
| CAT-1 | delegated | - | Core row: langsys-ruby CAT-1. Absence probe › "catalog inspection": lib/ tests no catalog entry for presence or value. |
| CAT-2 | delegated | - | Core row: langsys-ruby CAT-2. Absence probe › "catalog inspection". |
| CAT-3 | delegated | - | Core row: langsys-ruby CAT-3. Absence probe › "catalog inspection". |
| REG-1 | delegated | - | Core row: langsys-ruby REG-1. Absence probe › "capability decision". Observed live: `spec/integration/live_spec.rb` › "pushes nothing from a read-only key, while the same render on a write key does". |
| REG-2 | delegated | - | Core row: langsys-ruby REG-2. Absence probe › "send scheduling": no debounce, timer, sleep or thread in lib/. |
| REG-3 | implemented | live | The request-completion flush is owned here, per the core's declared REG-3 wrapper obligation: `RequestBoundary` calls the core's public `flush_pending` once the response is sent. `spec/integration/live_spec.rb` › "registers a render's miss only once the server closes the body" and › "registers a render's miss only once the server runs rack.response_finished" — both completion paths, server state read back through an uncached client. Worker shutdown is the core's best-effort `at_exit` (`config.langsys.auto_flush`, off by default as in the core); `Langsys::Rails.client.flush_pending` is the manual flush. Mutants `boundary-never-flushes`, `live-flush-on-the-request-path`. |
| REG-4 | n/a (profile: browser) | - | No page teardown on a server. |
| REG-5 | n/a (profile: browser) | - | No page teardown on a server. |
| REG-6 | delegated | - | Core row: langsys-ruby REG-6. Absence probe › "queue bookkeeping". |
| REG-7 | delegated | - | Core row: langsys-ruby REG-7. Absence probe › "queue bookkeeping". Concurrent request completions each call the core's `flush_pending`; its in-flight guard decides. |
| REG-8 | delegated | - | Core row: langsys-ruby REG-8. Absence probe › "queue bookkeeping". |
| REG-9 | delegated | - | Core row: langsys-ruby REG-9. Absence probe › "batching". |
| REG-10 | delegated | - | Core row: langsys-ruby REG-10. Absence probe › "failure handling": lib/ rescues nothing and logs nothing of its own — `handle_pending`'s rescue-and-warn is removed. |
| REG-11 | delegated | - | Core row: langsys-ruby REG-11. Absence probe › "ellipsis handling". |
| REG-12 | delegated | - | Core row: langsys-ruby REG-12. Absence probe › "catalog inspection". |
| HINT-1 | n/a (profile: browser) | - | Browser report lane. |
| HINT-2 | delegated | - | Core row: langsys-ruby HINT-2. Absence probe › "request construction": lib/ constructs no request and names no `discovery/hint`. |
| HINT-3 | n/a (profile: browser) | - | Browser report lane. |
| HINT-4 | n/a (profile: browser) | - | Browser report lane. |
| HINT-5 | n/a (profile: browser) | - | Browser report lane. |
| HINT-6 | n/a (profile: browser) | - | Browser report lane. |
| HINT-7 | n/a (profile: browser) | - | Browser report lane. |
| HINT-8 | n/a (profile: browser) | - | Browser report lane. |
| HINT-9 | n/a (profile: browser) | - | Browser report lane. |
| HINT-10 | n/a (profile: browser) | - | Browser report lane. |
| HINT-11 | n/a (profile: browser) | - | Browser report lane. |
| HINT-12 | n/a (profile: browser) | - | Browser report lane; the server mirror is the langsys backend. |
| ICU-1 | delegated | - | Core row: langsys-ruby ICU-1. Absence probe › "interpolation". BIND-1's vectors render a plural with its argument missing exactly as the core does. |
| ICU-2 | delegated | - | Core row: langsys-ruby ICU-2. Absence probe › "interpolation". BIND-1's vectors include null arguments. |
| ICU-3 | delegated | - | Core row: langsys-ruby ICU-3. Absence probe › "interpolation". |
| ICU-4 | delegated | - | Core row: langsys-ruby ICU-4. Absence probe › "interpolation". The notice reaches `Rails.logger` through the logger this binding passes (OBS-1). |
| ICU-5 | delegated | - | Core row: langsys-ruby ICU-5. Absence probe › "interpolation". |
| CID-1 | delegated | - | Core row: langsys-ruby CID-1. Absence probe › "content-block identity". |
| CID-2 | delegated | - | Core row: langsys-ruby CID-2. Absence probe › "content-block identity". |
| CID-3 | delegated | - | Core row: langsys-ruby CID-3. Absence probe › "content-block identity". |
| CID-4 | delegated | - | Core row: langsys-ruby CID-4. Absence probe › "content-block identity". |
| TOK-1 | delegated | - | Core row: langsys-ruby TOK-1. Absence probe › "tokenizer and host identity". |
| TOK-2 | delegated | - | Core row: langsys-ruby TOK-2. Absence probe › "tokenizer and host identity". |
| TOK-3 | delegated | - | Core row: langsys-ruby TOK-3. Absence probe › "tokenizer and host identity". |
| TOK-4 | delegated | - | Core row: langsys-ruby TOK-4. Absence probe › "tokenizer and host identity". |
| TOK-5 | delegated | - | Core row: langsys-ruby TOK-5. Absence probe › "tokenizer and host identity". BIND-1's vectors render `%name%` exactly as the core does. |
| MARK-1 | delegated | - | Core row: langsys-ruby MARK-1. Absence probe › "tokenizer and host identity": lib/ renders no host; `ls` returns text. |
| MARK-2 | delegated | - | Core row: langsys-ruby MARK-2. Absence probe › "tokenizer and host identity": lib/ reads no `data-ls-*` or `data-langsys-*` attribute. |
| SSR-1 | n/a (profile: browser) | - | SSR constrains the browser SDK under a server render. |
| SSR-2 | n/a (profile: browser) | - | SSR constrains the browser SDK under a server render. |
| SSR-3 | n/a (profile: browser) | - | SSR constrains the browser SDK under a server render. |
| SRV-1 | implemented | live | `spec/integration/live_spec.rb` › "serves the request locale's translation in the response bytes, and the base language only for a miss": `ls` under `?locale=es-ES` serves the fixture's `Soporte Técnico` in the response body, and a control phrase absent from the catalog serves its source text and is held by the server afterwards. Mutant `live-serves-base-language`. |
| SRV-2 | implemented | n/a (pure) | `spec/binding_conformance_spec.rb` › "serves each of two renders suspended mid-flight together only its own locale's text": a two-party rendezvous inside the render holds an es-ES and a de-DE request mid-walk at once, and the meeting itself is asserted, so a fall-back to sequential renders fails. Mutant `process-global-locale`. Tier: an isolation property a stateful fixture could not prove or disprove. |
| SRV-3 | implemented | live | Collection runs after the response is sent, on both completion paths: `spec/integration/live_spec.rb` › "registers a render's miss only once the server closes the body" and › "registers a render's miss only once the server runs rack.response_finished". Across overlapping requests: live › "holds a render's miss from another request's flush until its own response is sent" — request B completes and flushes while request A is held mid-render; the server holds B's miss (positive control) and not A's until A's response is out. `RequestBoundary` opens a core request scope per request and ends it before flushing; `spec/request_boundary_spec.rb` › "is open for the request that builds the client" and › "is released when the application raises, so its misses are not held until shutdown". A read-only key pushes nothing, with the same render on a write key as positive control (live › "pushes nothing from a read-only key, while the same render on a write key does"). Order of events for one request: › "posts nothing before the response is sent, even when the render outlasts the core's debounce window". Mutants `flush-on-the-request-path`, `response-finished-path-ignored`, `boundary-behind-the-executor`, `no-request-scope`, `scope-held-after-error`, `live-flush-on-the-request-path`, `live-response-finished-ignored`, `live-no-request-scope`. |
| SRV-4 | n/a (architecture: Rails views emit terminal HTML and this binding takes part in no hydration hand-off, so there is no client catalog to seed; live if the binding ever seeds a client-side Langsys SDK before hydration) | - | 8.0.1 scopes SRV-4 to an SDK that participates in a hydration hand-off. |
| SRV-5 | delegated | - | Core row: langsys-ruby SRV-5. Absence probe › "tokenizer and host identity": lib/ captures no component children (`ls` takes a string); subtree walks reached through `Langsys::Rails.client` are the core's. |
| BIND-1 | implemented | n/a (pure) | `spec/binding_conformance_spec.rb` › "renders and queues exactly what calling the core directly does": eight vectors (hit, miss, no category, `%name%`, a plural with its argument supplied, missing and null, a null plain argument), comparing output and the resulting queue with `Langsys::Client#translate` called directly; › "makes the ls helper the same call as Langsys::Rails.t". The binding's timing adaptations are the request boundary (GATE-3, REG-3, SRV-3). Mutant `t-adapts-meaning`. |
| BIND-2 | implemented | n/a (pure) | Absence probe › "capability decision" finds no capability value in lib/; firing control: core. Red-first: it found `can_write?` at `2751820` (`rails.rb:70`). Behaviour: `spec/request_boundary_spec.rb` › "does not discard a read-only session's queue; the core decides what happens to it". Mutant `boundary-branches-on-capability`. |
| BIND-3 | implemented | n/a (pure) | Absence probes › "request construction", › "send scheduling" and › "batching" find nothing in lib/; firing controls: core. The one network-adjacent act — calling the core's `flush_pending` when a request completes — is lifecycle timing, which BIND-1 permits and the core's CONFORMANCE assigns to this wrapper. |
| BIND-4 | partial | n/a (pure) | **Met for every core setting:** `spec/binding_conformance_spec.rb` › "names every core setting by the core client's own keyword", › "hands each configured core setting to the core client unchanged", › "gives auto_flush the core's meaning and the core's default" (the default is read from the core's source). `auto_flush` no longer means "flush after the request when writable". **Open:** `query_param`, `cookie_name` and `cookie_max_age` have no core equivalent — pinned by › "introduces exactly three settings the core has no equivalent for" and held unchanged pending the operator's ambient-locale ruling, which covers every server binding (What surfaced, items 5 and 6). Mutants `binding-only-setting`, `auto-flush-default-diverges`, `core-setting-dropped`. |
| BIND-5 | implemented | n/a (pure) | `spec/binding_conformance_spec.rb` › "shows a changed catalog on the very next call" and › "memoizes nothing but its own configuration objects". Mutant `lookup-results-memoized`. |
| BIND-6 | implemented | n/a (pure) | › "exposes the core client by reference plus framework idioms, and no behaviour of its own": the public surface is `configure`, `config`, `resolver`, `client`, `client=`, `reset_client!`, `t`, `locale` and the `ls` helper, and `client` is the core's `Langsys::Client`. `handle_pending`, a new behaviour name, is removed. Mutant `new-behaviour-name`. |
| GRANT-1 | n/a (profile: browser) | - | A grant lends write capability to a browser session; a server holds a write key. lib/ constructs no request (probe › "request construction"), so it cannot send `X-Write-Grant`. |
| GRANT-2 | n/a (profile: browser) | - | As GRANT-1. |
| GRANT-3 | n/a (profile: browser) | - | As GRANT-1. |
| GRANT-4 | n/a (profile: browser) | - | As GRANT-1. |
| CACHE-1 | delegated | - | Core row: langsys-ruby CACHE-1. Absence probe › "cache writes and keys". |
| OBS-1 | implemented | live | The binding's half is that the core's diagnostic reaches the host's log: the client is built with `logger:`, defaulting to `Rails.logger`. `spec/integration/live_spec.rb` › "puts the core's unusable-capability diagnostic in the Rails log, once across requests" (read key, three requests, exactly one line), with › "logs no such diagnostic on a write key (control)". Red-first: no line at `2751820`. When to emit is the core's OBS-1. Mutants `logger-not-passed`, `live-logger-not-passed`. |
| WIRE-1 | delegated | - | Core row: langsys-ruby WIRE-1. Absence probe › "request construction". |
| WIRE-2 | delegated | - | Core row: langsys-ruby WIRE-2. Absence probe › "request construction". |
| WIRE-3 | delegated | - | Core row: langsys-ruby WIRE-3. Absence probe › "request construction": lib/ never forms the wire locale; the display form in the cookie and `CurrentLocale` comes from the core's `Langsys.canonicalize_locale`. |
| WIRE-4 | implemented | live | Binding code sits on every request path — locale resolution and the request boundary — so that half is owned here. `spec/integration/live_spec.rb` › "serves the page in the source language when the API refuses the key, and records nothing": the live server rejects the key, the page is 200 in its source text, nothing is queued. `spec/request_boundary_spec.rb` › "neither builds a client nor raises for a request that never translated": with no credentials, a non-translating route is still 200. Mutants `raising-lookup-on-request-path`, `live-raising-lookup-on-request-path`, `boundary-builds-a-client`. |
| WIRE-5 | implemented | live | `api_url` passes through to the core and is documented in the README's Setup and Configuration sections. `spec/integration/live_spec.rb` › "takes a redirect made after first use: a dead address degrades, then the live one translates": the Spanish can only have come from the live server, so the redirect arrived; reconfiguring rebuilds the client, so the too-late failure WIRE-5 names cannot happen. Mutants `stale-client-after-redirect`, `live-stale-client-after-redirect`. |
| CONF-1 | implemented | n/a (pure) | Every row graded `live` asserts on the served bytes or on server state read back through a separate, uncached client — never on what the binding sent. Every-path clause: REG-3 and SRV-3 are proven on both completion paths (body close and `rack.response_finished`), GATE-7 on both entry points (`t` and `ls`). WebMock-backed examples carry no `live` or `contract` grade. |
| CONF-2 | implemented | n/a (pure) | Every row carries a canonical tier. `spec/conformance_doc_spec.rb` checks the header rows, one status table, all 79 ids once each in spec order, the status and tier vocabulary, the tiers each status permits, and a summary computed from the table. Mutant `summary-drifts-from-table`. |
| CONF-3 | implemented | n/a (pure) | `spec/mutation/manifest.rb`, run by `rake mutation` (22 hermetic mutants) and `rake mutation:live` (7 live). An entry must apply exactly once; its examples must be green, with none pending, before the edit, and red without a load error after it; the file is then restored byte for byte. Result on this tree: 22/22 hermetic and 7/7 live mutants killed. |

## Summary

Computed from the table above; `spec/conformance_doc_spec.rb` fails the build when they disagree.

| Status | Count |
|---|---|
| implemented | 17 |
| delegated | 39 |
| partial | 1 |
| n/a (profile: browser) | 20 |
| n/a (architecture) | 2 |
| total | 79 |

## Obligations taken over from `langsys-ruby`

The core's CONFORMANCE.md declares two things its process-wide client cannot do for itself and
names this repo as their owner. Both are wired in `Langsys::Rails::RequestBoundary`, which the
Railtie inserts in front of `ActionDispatch::Executor`:

- **GATE-3 — the request-boundary reset.** `Client#reset_write_decision!` as a request enters and
  again once it completes.
- **REG-3 — the host lifecycle flush.** `Client#flush_pending` once the response has been sent,
  on whichever completion path the server provides, inside a core request scope
  (`Langsys.begin_request_scope` / `Langsys.end_request_scope`) so no other request's flush
  sends this request's misses early (SRV-3).

## Gaps, ranked by cost

1. **No `Vary` on a negotiated response** (BIND-4, pending the ambient-locale ruling). An app
   that marks a localized page public has a shared cache serve one visitor's language to the next
   — SRV-1's harm, arriving through the cache. Customer-visible, and costly in search.
2. **Unvalidated `?locale=` kept for a year** (BIND-4, same ruling). A crafted link pins a
   browser to a failed catalog round trip on every request. Latency for that visitor, load on the
   API.
3. **Three binding-only settings** (BIND-4, same ruling). Ownership of configuration, no runtime
   cost.

## Release wave

- **The base gem is unpublished.** `Gemfile` points `langsys` at `../langsys-ruby` for
  co-development. At publication: publish `langsys` first, delete that line (the gemspec already
  requires `langsys >= 0.1.0`), then publish this gem.
- **`Gemfile.lock` is gitignored.** The program's survey `bundle check` rewrote it. A
  `bundle lock --local` regeneration re-resolved against locally installed gems (json 2.21.2 to
  3.0.2, rubocop 1.90 to 1.91), so the prior lock was restored and verified unchanged by
  `bundle install --local`; the suite is measured under json 2.21.2.

## Provenance

The commands, not the values, are the record:

```
# The spec blob and rule ids this file rows against
git -C ../langsys2 ls-tree 5cff03a17751e7dae9dcf1af52a9454d027c9006 docs/sdk-spec.mdx
#   -> 5c5c0723f88fb8e6b13f58876c7adca8b6b35691
git -C ../langsys2 cat-file blob 5c5c0723 | grep -cE '^### [A-Z]+-[0-9]+ '
#   -> 79

# Hermetic suite, lint, signatures, hermetic mutants
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
- Live evidence runs against the local 838 stack on this repo's own fixture project, where
  registration is synchronous; nothing downstream of registration is asserted.
- `delegated` rows name the core's row, not its grade. The program's checker resolves each against
  langsys-ruby's current CONFORMANCE.md, so a regression there reaches this file without an edit
  here.
- The WebMock-backed examples are hermetic twins of the live ones. They grade nothing that depends
  on what the API answers; they exist so the mutation run needs no backend.
