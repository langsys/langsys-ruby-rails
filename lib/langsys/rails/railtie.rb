# frozen_string_literal: true

require "rails/railtie"

require_relative "controller"
require_relative "helper"

module Langsys
  module Rails
    # Wires the wrapper into a Rails app: reads +config.langsys+, then auto-includes the
    # controller concern and the view helper.
    class Railtie < ::Rails::Railtie
      # Apps configure via `config.langsys.api_key = …` etc. in an initializer / environment.
      config.langsys = ActiveSupport::OrderedOptions.new

      SETTINGS = %i[
        api_key project_id api_url base_locale supported
        query_param cookie_name cookie_max_age auto_flush cache cache_ttl timeout
      ].freeze

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
