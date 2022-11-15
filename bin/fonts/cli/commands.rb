# frozen_string_literal: true
require 'dry/cli/registry'
require_relative 'commands/version'
require_relative 'commands/fetch'
require_relative 'commands/upsert'
require_relative 'commands/preview'

module Fonts
  module CLI
    module Commands
      extend Dry::CLI::Registry

      register 'version', Version, aliases: ['v', '-v', '--version']
      register 'fetch', Fetch
      register 'upsert', Upsert
      register 'preview', Preview
    end
  end
end