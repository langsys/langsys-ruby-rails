# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial Rails integration over the `langsys` base gem: a per-request locale backed by
  `ActiveSupport::CurrentAttributes`, a controller concern that resolves the locale from the
  query string / cookie / `Accept-Language` header (persisting an explicit choice to a
  cookie) and registers discovered phrases after the response, an `ls` view/controller
  helper, and a Railtie reading `config.langsys`.
