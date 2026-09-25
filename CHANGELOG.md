# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Validation errors as translatable entries: `Langsys::Rails::Messages.entries(record)` builds them
  from the failed rules and their options, with each field's `human_attribute_name` written into
  the sentence; `ls_message(entry)` renders one in the request locale. Templates Langsys lacks are
  registered after the response.
- `rake langsys:messages` lists every validation template an app can emit and exits non-zero
  naming each field with no label and each custom rule without declared templates;
  `REGISTER=1` registers them. Models declare custom templates with `langsys_message_templates`.
- Migration mode: with `config.langsys.migration` set, `I18n.t` and the `t` view helper look an
  argument up as a key in the named source files first and treat anything else as source text.
- `langsys_resolved_attributes`, for a layout's root element on a page rendered in a translated
  locale.
- `messages_category`, `migration` and `migration_locale` settings, passed to the base SDK.
- A `snapshot` setting: a catalog snapshot the app loads at boot, so the first request renders with
  no fetch; a snapshot the base SDK refuses fails the boot.

### Changed

- The request locale comes from the base SDK's resolution: the URL parameter, then the locale
  cookie, then `Accept-Language`, each validated against the project's locales. The response
  carries `Vary` for whatever the choice depended on, and only a locale chosen in the URL is
  written to the cookie.
- Each request runs in a base-SDK request scope, so a phrase it discovers is registered only once
  its own response has been sent.
- Requires `activemodel`.

### Removed

- The `supported` setting and `Langsys::Rails.resolver`: the project's locales in Langsys decide
  what is served.

### Changed

- Discovered phrases are registered after the response has been sent, by
  `Langsys::Rails::RequestBoundary` — Rack middleware the Railtie inserts in front of
  `ActionDispatch::Executor`. An `after_action` used to register them on the request path,
  inside the visitor's wait (SRV-3).
- The wrapper no longer decides whether a session may write. It used to flush on a writable
  session and discard the queue otherwise; the base SDK now makes that decision (BIND-2).
- `auto_flush` now carries the base SDK's meaning — its best-effort flush at process exit —
  and its default, `false`. The per-request flush is always on (BIND-4).
- `Langsys::Rails.handle_pending` is removed. `Langsys::Rails.client.flush_pending` is the
  manual flush (BIND-6).

### Fixed

- The base SDK's write decision no longer outlives a request: it is dropped as each request
  enters and again once it is done (GATE-3).
- The base SDK's diagnostics reach the log. The client is built with a `logger`, defaulting to
  `Rails.logger`; previously none was passed, so its one-time warning that a session cannot
  write went nowhere (OBS-1).

### Added

- A `logger` setting.
- `CONFORMANCE.md`, a live integration suite (`rake integration`) and a mutation harness
  (`rake mutation`, `rake mutation:live`).

### Added

- Initial Rails integration over the `langsys` base gem: a per-request locale backed by
  `ActiveSupport::CurrentAttributes`, a controller concern that resolves the locale from the
  query string / cookie / `Accept-Language` header (persisting an explicit choice to a
  cookie) and registers discovered phrases after the response, an `ls` view/controller
  helper, and a Railtie reading `config.langsys`.
