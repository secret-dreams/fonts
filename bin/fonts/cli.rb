# frozen_string_literal: true

require 'dry/cli'
require_relative 'cli/commands'

module Fonts
  module CLI
    def self.call
      Dry::CLI.new(Fonts::CLI::Commands).call
    end
  end
end