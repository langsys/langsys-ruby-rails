# frozen_string_literal: true

module Langsys
  module Rails
    # View + controller helper. +ls+ is short for "Langsys string".
    #
    #   <%= ls "Save", "UI" %>
    #   <%= ls "Hello, {name}!", "Greetings", name: current_user.name %>
    module Helper
      def ls(phrase, category = nil, **params)
        Langsys::Rails.t(phrase, category, **params)
      end
    end
  end
end
