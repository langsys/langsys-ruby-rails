# frozen_string_literal: true

module Langsys
  module Rails
    # View + controller helpers.
    #
    #   <%= ls "Save", "UI" %>
    #   <%= ls "Hello, {name}!", "Greetings", name: current_user.name %>
    #   <%= tag.html(**langsys_resolved_attributes) do %> … <% end %>
    #   <% Langsys::Rails::Messages.entries(@user).each do |entry| %><%= ls_message(entry) %><% end %>
    module Helper
      # "Langsys string": the base SDK's translation for the current request locale.
      def ls(phrase, category = nil, **params)
        Langsys::Rails.t(phrase, category, **params)
      end

      # A server-message entry in the request locale (MSG-5): the catalog's translation of its
      # template, filled from its params, or its +message+ when there is none. The base SDK's
      # +render_message+; +message+ is never used as a lookup key.
      def ls_message(entry)
        Langsys::Rails.client.render_message(entry)
      end

      # The attribute that marks a page as resolved output (GATE-10), for the layout's root
      # element. +ls+ prints translated text inline, so a page rendered in a locale other than
      # the project's base is not source; a Langsys SDK walking that page must not register it.
      # Empty on a base-locale render, which is source and stays discoverable, and empty when
      # the project's base locale cannot be read. The decision is the base SDK's
      # +Client#resolved_locale+, the one its +translate_page+ makes for <html>.
      def langsys_resolved_attributes
        locale = Langsys::Rails.client.resolved_locale
        locale ? { "data-ls-resolved" => locale } : {}
      end
    end
  end
end
