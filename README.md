# langsys-rails

Rails integration for the [Langsys](https://langsys.dev) Translation Manager — a **thin
wrapper** over the [`langsys`](https://github.com/langsys/langsys-ruby) base gem. It adds only
the Rails-idiomatic pieces (a per-request locale, a controller concern, an `ls` view helper, a
Railtie) and delegates all translation to the base SDK.

The phrase in your code is the lookup key **and** the base-language default — no keys file, no
extraction step. Untranslated phrases render as the source phrase.

## Install

```ruby
# Gemfile
gem "langsys-rails"
```

Then `bundle install`. Requires Ruby 3.0+ and Rails 6.1+.

## Setup

Configure in `config/initializers/langsys.rb` (or per environment):

```ruby
Rails.application.config.langsys.api_key    = ENV["LANGSYS_API_KEY"]     # read key = fetch-only
Rails.application.config.langsys.project_id = ENV["LANGSYS_PROJECT_ID"]  # write key = auto-registers
Rails.application.config.langsys.base_locale = "en-US"
Rails.application.config.langsys.supported  = %w[en-US es-ES fr-FR de-DE]
# Rails.application.config.langsys.api_url = "http://localhost:8000/api"  # self-hosted backend
```

Credentials left unset fall back to the base SDK's `LANGSYS_API_KEY` / `LANGSYS_PROJECT_ID`
environment variables. That's all — the Railtie auto-includes the controller concern and the
view helper, and resolves the locale on every request.

## Translating

### In views — the `ls` helper

```erb
<%= ls "Save" %>
<%= ls "Save", "UI" %>
<%= ls "Hello, {name}!", "Greetings", name: current_user.name %>
```

The category is part of the key, so the same word can be translated differently per context:

```erb
<%= ls "Home", "Main Menu" %>   <%# the nav item %>
<%= ls "Home", "Home repairs" %> <%# the building %>
```

### In controllers, models, jobs — `Langsys::Rails.t`

```ruby
Langsys::Rails.t("Welcome back, {name}!", "Greetings", name: user.name)
```

Params accept strings, numbers, `Date`/`Time`, and booleans — numbers and dates are CLDR-
formatted in the loaded locale. ICU MessageFormat (plurals, select) works too:

```ruby
Langsys::Rails.t("You have {n, plural, one {# item} other {# items}}.", "Cart", n: cart.size)
```

## How the locale is resolved

Before each action the concern picks the request locale in order: `?locale=`, then the
`langsys_locale` cookie, then the `Accept-Language` header (matched against `supported`). An
explicit `?locale=` choice is persisted to the cookie so it sticks across requests. The locale
lives in `ActiveSupport::CurrentAttributes` for the duration of the request — which Rails
resets automatically — so a single shared client is safe across concurrent requests.

A simple locale switcher is just a set of links:

```erb
<% %w[en-US es-ES fr-FR de-DE].each do |code| %>
  <%= link_to code, url_for(locale: code) %>
<% end %>
```

Phrases discovered while rendering are registered **after the response has been sent**, never
while the visitor waits. The Railtie inserts `Langsys::Rails::RequestBoundary` in front of
`ActionDispatch::Executor` to do that; it flushes through the base SDK, which alone decides
whether this session may write. On a read-only key nothing is sent, and the base SDK logs that
once per process. The same middleware drops the base SDK's write decision at every request
boundary, so a decision made for one request is never reused for the next.

> **Caching.** The locale is negotiated from the query string, a cookie and `Accept-Language`,
> and the response does not carry `Vary`. Rails' default `Cache-Control: private` keeps shared
> caches from storing these pages. If you mark a localized response public (`expires_in …,
> public: true`), add `Vary: Accept-Language, Cookie` yourself, or a CDN will serve one
> visitor's language to the next.

## Server-side HTML translation

Reach the full base SDK through `Langsys::Rails.client` — including HTML translation (needs
`gem "nokogiri"`):

```ruby
Langsys::Rails.client.translate_content_block(html, category: "Home")
Langsys::Rails.client.translate_page(rendered_html)
```

## Configuration

Set any of these on `config.langsys`:

| Setting | Default | Notes |
|---------|---------|-------|
| `api_key` / `project_id` | `LANGSYS_*` env | required (directly or via env) |
| `api_url` | `https://api.langsys.dev/api` | self-hosted backend |
| `base_locale` | project's base locale | |
| `supported` | `[]` | locale allow-list for `Accept-Language` matching |
| `query_param` | `"locale"` | the switch query param |
| `cookie_name` | `"langsys_locale"` | |
| `cookie_max_age` | `31_536_000` | one year, in seconds |
| `auto_flush` | `false` | the base SDK's best-effort flush at process exit; the per-request flush is always on |
| `logger` | `Rails.logger` | receives the base SDK's diagnostics |
| `cache` / `cache_ttl` / `timeout` | base SDK defaults | e.g. `Langsys::Cache::Memory.new` |

## Development

```bash
bundle install
bundle exec rake spec          # hermetic
bundle exec rubocop
bundle exec rake rbs           # validate the RBS type signatures
bundle exec rake mutation      # CONF-3: every hermetic mutant must turn its tests red
```

The live suite and its mutations run against a local Langsys backend, with the fixed local-only
credentials langsys2's `SdkIntegrationSeeder` creates for this repo:

```bash
export LANGSYS_API_URL=http://langsys2.test/api
export LANGSYS_PROJECT_ID=c0de0000-5d10-4000-8000-000000000013
export LANGSYS_API_KEY=sdk_integration_rails_local_only_do_not_deploy
export LANGSYS_READ_KEY=sdk_integration_rails_read_local_only_do_not_deploy
bundle exec rake integration
bundle exec rake mutation:live
```

`CONFORMANCE.md` maps every rule of the Langsys SDK Behaviour Spec to the test that proves it.

Type signatures for the public API ship in `sig/` (RBS).

## Releasing

Published to [RubyGems](https://rubygems.org) manually. Publish the `langsys` base gem first
(this depends on it), then bump `Langsys::Rails::VERSION`, update `CHANGELOG.md`, and:

```bash
gem build langsys-rails.gemspec
gem push langsys-rails-<version>.gem   # requires a RubyGems account with push access
```

## License

MIT
