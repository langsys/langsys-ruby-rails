# frozen_string_literal: true

require "rails/railtie"
require "action_dispatch"

require_relative "controller"
require_relative "helper"
require_relative "request_boundary"

module Langsys
  module Rails
    # Wires the wrapper into a Rails app: reads +config.langsys+, inserts the request boundary,
    # and auto-includes the controller concern and the view helper.
    class Railtie < ::Rails::Railtie
      # Apps configure via `config.langsys.api_key = …` etc. in an initializer / environment.
      config.langsys = ActiveSupport::OrderedOptions.new

      SETTINGS = (Config::CORE_SETTINGS + Config::LOCALE_SETTINGS).freeze

      # In front of the executor, so the post-response flush runs after Rails has completed the
      # request on both of the paths RequestBoundary supports.
      config.app_middleware.insert_before ActionDispatch::Executor, RequestBoundary

      initializer "langsys.configure" do |app|
        options = app.config.langsys
        Langsys::Rails.configure do |config|
          SETTINGS.each do |key|
            value = options[key]
            config.public_send("#{key}=", value) unless value.nil?
          end
        end
      end

      initializer "langsys.integrate" do
        ActiveSupport.on_load(:action_controller) { include Langsys::Rails::Controller }
        ActiveSupport.on_load(:action_view) { include Langsys::Rails::Helper }
      end
    end
  end
end
