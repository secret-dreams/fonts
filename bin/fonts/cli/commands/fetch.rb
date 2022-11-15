# frozen_string_literal: true
require 'dry/cli/command'
require 'json'
require 'faraday'
require 'parallel'
require 'down/http'
require 'active_support/inflector'

module Fonts
  module CLI
    module Commands
      class Fetch < Dry::CLI::Command
        desc 'Fetch upstream fonts'

        argument :root, required: true, desc: 'Root directory to which fonts will be imported'
        argument :fonts_json_uri, required: false, desc: 'JSON sourcefile for fonts', default: 'https://help.shopify.com/json/shopify_font_families.json'
        argument :parallel, required: false, desc: 'Run job in parallel', default: 10
        argument :force, required: false, desc: 'Overwrite existing files', default: false

        example [
                    "path/to/root # Saves fonts at root directory"
                ]

        def call(root:, fonts_json_uri:, parallel:, force:, **)
          root          = File.expand_path(root, Dir.pwd)
          font_families = Faraday.get(fonts_json_uri, request_headers)
                              .then { |r| JSON.parse(r.body).dig('font_families') }

          Parallel.map(font_families, in_threads: (parallel || 1).to_i, progress: 'Downloading font families') do |font_family|
            download_font_family(font_family: font_family, directory: root, force: force)
          end
        end

        private

        def download_font_family(font_family:, directory:, force: false)
          font_family      = font_family.dup
          font_family_slug = ActiveSupport::Inflector.parameterize(font_family['name'])
          directory        = File.join(directory, font_family_slug)

          if force && File.directory?(directory)
            puts "Directory #{directory} already existed, removing"
            FileUtils.remove_dir(directory)
          end
          return if File.directory?(directory)

          FileUtils.mkdir_p(directory)

          # Persist fonts assets
          font_family['variants'].each do |font_variant|
            _preview_urls        = font_variant.delete('preview_urls') { [] }
            formats              = font_variant.delete('urls') { [] }
            font_variant['urls'] = formats.map do |font_format, font_uri|
              file_name      = [font_variant['handle'], font_format].join('.')
              file_path      = File.join(directory, file_name)
              _file_download = ::Down::Http.download(font_uri, headers: request_headers, destination: file_path)

              [font_format, file_name]
            end.to_h
          end

          # Persist fonts specs
          File.open(File.join(directory, 'font_family.json'), 'w') do |f|
            f.write(JSON.pretty_generate(font_family))
          end

        end

        def request_headers
          {
              'referer'    => 'https://help.shopify.com/',
              'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.108 Safari/537.36'
          }
        end

      end
    end
  end
end