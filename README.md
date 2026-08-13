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

With a **write** key, phrases discovered while rendering are registered after the response;
with a **read** key nothing is written (the queue is dropped so it can't grow unbounded).
Toggle with `config.langsys.auto_flush = false`.

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
| `auto_flush` | `true` | register discovered phrases after the response (write key) |
| `cache` / `cache_ttl` / `timeout` | base SDK defaults | e.g. `Langsys::Cache::Memory.new` |

## Development

```bash
bundle install
bundle exec rake spec
bundle exec rubocop
bundle exec rake rbs   # validate the RBS type signatures
```

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
