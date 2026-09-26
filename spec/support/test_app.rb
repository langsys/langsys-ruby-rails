# frozen_string_literal: true

require "rails"
require "action_controller/railtie"
require "langsys/rails/railtie" # register the Railtie now that ::Rails::Railtie exists
require "rack/test"
require_relative "models"

APP_SETTINGS = {
  api_key: "test-key", project_id: "proj-1", api_url: API_URL,
  base_locale: "en-US"
}.freeze

# What PlanController renders, and what it saw of the core's write decision. Set per example.
module RenderPlan
  class << self
    attr_accessor :phrases, :signal_at_entry, :signal_after_render

    def reset!
      self.phrases = []
      self.signal_at_entry = :unset
      self.signal_after_render = :unset
    end
  end
  reset!
end

# The order a request's events happened in, across threads — SRV-3 asserts on order.
module EventLog
  @events = []
  @mutex = Mutex.new

  class << self
    def record(event) = @mutex.synchronize { @events << event }
    def events = @mutex.synchronize { @events.dup }
    def reset! = @mutex.synchronize { @events.clear }
  end
end

# An N-party rendezvous with a timeout, so a test can prove renders were suspended
# mid-flight at the same moment rather than merely run one after another.
class Rendezvous
  def initialize(parties:, timeout: 5)
    @parties = parties
    @timeout = timeout
    @arrived = 0
    @met = false
    @mutex = Mutex.new
    @cond = ConditionVariable.new
  end

  def met? = @mutex.synchronize { @met }

  def wait!
    @mutex.synchronize do
      @arrived += 1
      @met = true if @arrived >= @parties
      @cond.broadcast
      await_met
    end
  end

  private

  # Called holding @mutex.
  def await_met
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
    until @met
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if remaining <= 0

      @cond.wait(@mutex, remaining)
    end
  end
end

module RackHelpers
  def call_app(path, env = {})
    request_env = Rack::MockRequest.env_for(path).merge(env)
    status, headers, body = LangsysTestApp.call(request_env)
    [request_env, status, headers, body]
  end

  # A Rack body promises only #each, so it is read the way a server reads it.
  def read_body(body)
    buffer = +""
    body.each { |chunk| buffer << chunk }
    buffer
  end

  # What a server providing rack.response_finished does once the response is processed.
  def finish_response(env, status, headers)
    env["rack.response_finished"].reverse_each { |callable| callable.call(env, status, headers, nil) }
  end
end

class GreetingsController < ActionController::Base
  def show
    render plain: ls("Save", "UI")
  end
end

class VaryController < ActionController::Base
  def show
    response.headers["Vary"] = "Origin"
    render plain: ls("Save", "UI")
  end
end

class LayoutController < ActionController::Base
  def show
    render inline: "<%= tag.html(**langsys_resolved_attributes) { ls('Save', 'UI') } %>"
  end
end

# A failed form: the entries its validation produced, rendered in the request locale.
class SignupsController < ActionController::Base
  def create
    signup = Signup.new(email: params[:email], age: 30, tags: [], starts_on: Date.new(2026, 6, 1))
    signup.valid?
    render plain: Langsys::Rails::Messages.entries(signup).map { |entry| ls_message(entry) }.join("\n"),
           status: :unprocessable_content
  end
end

# An app that resolves the locale itself, the Rails-guide way (SRV-6).
class AppLocaleController < ActionController::Base
  around_action :switch_locale

  def show
    render plain: ls("Save", "UI")
  end

  private

  def switch_locale(&block)
    I18n.with_locale(params[:app_locale], &block)
  end
end

class PlanController < ActionController::Base
  def show
    RenderPlan.signal_at_entry = Langsys::Rails.client.write_signal
    body = RenderPlan.phrases.map { |phrase, category| ls(phrase, category) }.join("\n")
    RenderPlan.signal_after_render = Langsys::Rails.client.write_signal
    render plain: body
  end
end

class ConcurrentController < ActionController::Base
  cattr_accessor :rendezvous

  def show
    first = ls("Save", "UI")
    self.class.rendezvous.wait!
    render plain: "#{first}|#{ls('Cancel', 'UI')}"
  end
end

# Records a miss, runs an optional hold mid-render, translates again, then renders.
class EventsController < ActionController::Base
  cattr_accessor :hold

  def show
    tag = params.fetch(:tag)
    ls("Miss #{tag}", "UI")
    EventLog.record("#{tag}:miss-recorded")
    self.class.hold&.call(tag)
    ls("Save", "UI")
    EventLog.record("#{tag}:rendered")
    render plain: tag
  end
end

class LangsysTestApp < Rails::Application
  config.eager_load = false
  config.enable_reloading = false
  config.consider_all_requests_local = true
  config.secret_key_base = "test-secret-key-base"
  config.logger = Logger.new(IO::NULL)
  config.hosts.clear
  APP_SETTINGS.each { |key, value| config.langsys.public_send("#{key}=", value) }
end

LangsysTestApp.initialize!
LangsysTestApp.routes.draw do
  get "/greet" => "greetings#show"
  get "/plan" => "plan#show"
  get "/concurrent" => "concurrent#show"
  get "/events" => "events#show"
  get "/vary" => "vary#show"
  get "/layout" => "layout#show"
  get "/app_locale" => "app_locale#show"
  post "/signups" => "signups#create"
  get "/health", to: ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }
end

RSpec.configure do |config|
  # Every request asks the core which locales the project serves (SRV-6). A default answer
  # — a write key, base en-us, targets es-es and de-de — which an example overrides by
  # stubbing authorize again (WebMock prefers the latest stub).
  config.before { stub_authorize }

  config.around do |example|
    enforced = I18n.enforce_available_locales
    I18n.enforce_available_locales = false
    example.run
  ensure
    I18n.config.locale = nil # no example inherits the locale another example set
    I18n.enforce_available_locales = enforced
  end

  config.after do
    RenderPlan.reset!
    EventLog.reset!
    ConcurrentController.rendezvous = nil
    EventsController.hold = nil
  end
end
