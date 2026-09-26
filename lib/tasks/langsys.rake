# frozen_string_literal: true

namespace :langsys do
  desc "List every server-message template this app can emit (MSG-7); REGISTER=1 registers the new ones. " \
       "Reports each message it cannot list; STRICT=1 exits non-zero when there is one."
  task messages: :environment do
    Rails.application.eager_load!
    sources = Langsys::Messages.sources + [Langsys::Rails::ValidatorSource.new]
    status = Langsys::Messages::Command.run(sources: sources, client: Langsys::Rails.client,
                                            register: ENV["REGISTER"] == "1", strict: ENV["STRICT"] == "1")
    exit(status) unless status.zero?
  end
end
