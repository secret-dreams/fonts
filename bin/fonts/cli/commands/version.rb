# frozen_string_literal: true
require 'dry/cli/command'

module Fonts
  module CLI
    module Commands
      class Version < Dry::CLI::Command
        desc 'Print version'

        def call(*)
          puts '1.0.4'
        end
      end
    end
  end
end