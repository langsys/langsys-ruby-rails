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

Then `bundle install`. Requires Ruby 3.0+ and Rails 6.1+ (ActionPack, ActiveModel, Railties).

## Setup

Configure in `config/initializers/langsys.rb` (or per environment):

```ruby
Rails.application.config.langsys.api_key    = ENV["LANGSYS_API_KEY"]     # read key = fetch-only
Rails.application.config.langsys.project_id = ENV["LANGSYS_PROJECT_ID"]  # write key = auto-registers
Rails.application.config.langsys.base_locale = "en-US"
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

Before each action the concern asks the base SDK for the request locale, taking the first usable
candidate from, in order: the `locale` URL parameter (a query parameter, or a route segment named
`locale`), the `langsys_locale` cookie, then `Accept-Language`, and otherwise the project's base
locale. Every candidate is validated against the locales your project serves — its base and
target locales in Langsys — so an unsupported value is skipped, never served and never stored.

- A choice taken from the URL is remembered in the cookie, so it sticks across requests. A locale
  that came from the cookie or the header is never written back.
- The response names what the choice depended on: `Vary: Cookie` when the cookie decided it,
  `Vary: Accept-Language` when the header did, and nothing extra when the URL did (the URL is
  already the cache key). A `Vary` your app sets is kept. This is what lets a CDN cache localized
  pages without serving one visitor's language to the next.

The locale lives in `ActiveSupport::CurrentAttributes` for the duration of the request — which
Rails resets automatically — so a single shared client is safe across concurrent requests.

A simple locale switcher is just a set of links:

```erb
<% %w[en-US es-ES fr-FR de-DE].each do |code| %>
  <%= link_to code, url_for(locale: code) %>
<% end %>
```

### Marking translated pages

`ls` prints translated text straight into your HTML. If a Langsys JavaScript SDK also runs on the
page, mark the layout's root so it does not mistake that translated text for source:

```erb
<%= tag.html(**langsys_resolved_attributes, lang: Langsys::Rails.locale) do %>
  …
<% end %>
```

`langsys_resolved_attributes` is `data-ls-resolved="es-es"` on a page rendered in a locale other
than your project's base, and empty on a base-locale page, which stays discoverable.

## Registering discovered phrases

Phrases discovered while rendering are registered **after the response has been sent**, never
while the visitor waits. The Railtie inserts `Langsys::Rails::RequestBoundary` in front of
`ActionDispatch::Executor` to do that. Each request runs in its own scope, so a phrase is sent
only once its own response is out, even when another request finishes first. The base SDK alone
decides whether this session may write: on a read-only key nothing is sent, and it logs that once
per process to `Rails.logger`. The middleware also drops the base SDK's write decision at every
request boundary, so a decision made for one request is never reused for the next.

## Validation errors

Validation errors never appear on a page a visitor's browser renders by itself, so Langsys cannot
discover them the way it discovers other text. `Langsys::Rails::Messages.entries` turns a model's
failed validations into translatable entries, and `ls_message` renders one in the request locale:

```erb
<% Langsys::Rails::Messages.entries(@user).each do |entry| %>
  <p class="error" data-field="<%= entry["field"] %>"><%= ls_message(entry) %></p>
<% end %>
```

Each entry is `{ "field", "code", "message", "template", "params" }`. `code` is a stable slug to
branch on (`required`, `too_short`, `invalid_format`, …) — never use it to choose text. `template`
is a whole sentence with the field's label written in, taken from `human_attribute_name` (so
declare your labels in `config/locales/*.yml`); only numbers and dates travel in `params`.
`message` is the filled template, which `ls_message` shows when there is no translation yet. An
API can return the entries in its own error body, or in the default shape from
`Langsys::Messages.envelope(entries)`.

A template Langsys has not seen is registered after the response, like any discovered phrase. To
register every template ahead of time — and fail CI on any message that cannot be — run:

```bash
bin/rails langsys:messages               # lists every template; exits non-zero naming each problem
REGISTER=1 bin/rails langsys:messages    # also registers the ones Langsys has not seen
```

It reports a validated field with no declared label, and a custom validator or `validate`
method whose templates you have not declared. Declare those on the model:

```ruby
def self.langsys_message_templates
  { starts_on: ["The start date cannot be a holiday."] }
end
```

## Migrating from Rails I18n keys

An app keyed on `config/locales/*.yml` can move to Langsys without a codemod. Keep only your
source-language file and turn on migration mode:

```ruby
Rails.application.config.langsys.migration        = [Rails.root.join("config/locales/en.yml").to_s]
Rails.application.config.langsys.migration_locale = "en"
```

`I18n.t` and the `t` view helper then look an argument up as a key in that file first: a hit
translates the key's English value (its namespace becomes the category, and a `zero`/`one`/`other`
hash becomes one ICU plural); a string that is not a key is treated as English source text. Rails'
own translations, and lookups with a `scope:` or `default:`, are unaffected. Mode off (the
default), nothing changes.

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
| `query_param` | `"locale"` | the URL parameter that selects the locale |
| `cookie_name` | `"langsys_locale"` | remembers a locale chosen in the URL |
| `cookie_max_age` | `31_536_000` | one year, in seconds |
| `auto_flush` | `false` | the base SDK's best-effort flush at process exit; the per-request flush is always on |
| `logger` | `Rails.logger` | receives the base SDK's diagnostics |
| `messages_category` | `"Errors"` | category validation-error templates register under |
| `migration` / `migration_locale` | off | source-language files for migration mode |
| `cache` / `cache_ttl` / `timeout` | base SDK defaults | e.g. `Langsys::Cache::Memory.new` |

## Development

```bash
bundle install
bundle exec rake spec          # hermetic; the contract-double specs need Node 18+
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
