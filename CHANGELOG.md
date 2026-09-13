# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
