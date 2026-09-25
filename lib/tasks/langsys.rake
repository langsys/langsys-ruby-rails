# frozen_string_literal: true

namespace :langsys do
  desc "List every server-message template this app can emit (MSG-7); REGISTER=1 registers the new ones. " \
       "Exits non-zero naming each message that cannot be listed."
  task messages: :environment do
    Rails.application.eager_load!
    sources = Langsys::Messages.sources + [Langsys::Rails::ValidatorSource.new]
    status = Langsys::Messages::Command.run(sources: sources, client: Langsys::Rails.client,
                                            register: ENV["REGISTER"] == "1")
    exit(status) unless status.zero?
  end
end
