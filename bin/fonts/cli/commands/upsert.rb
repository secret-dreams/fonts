# frozen_string_literal: true

require 'dry/cli/command'
require 'json'
require 'faraday'
require 'parallel'
require 'pathname'
require 'retriable'

module Fonts
  module CLI
    module Commands
      class Upsert < Dry::CLI::Command
        class DdosProtectionException < StandardError; end

        HTTP_RETRY_EXCEPTIONS = [Faraday::TimeoutError, DdosProtectionException]

        desc 'Upsert fonts to remote service'

        argument :root, required: true, desc: 'Root directory from which fonts will be imported'

        option :service, desc: 'JSON sourcefile for fonts', default: 'http://localhost:3000'
        option :service_user, desc: 'Service username', default: nil
        option :service_password, desc: 'Service username', default: nil
        option :force, desc: 'Overwrite existing files', default: false
        option :specification_file, desc: 'Name of file that describes font family', default: 'font_family.json'
        option :parallel, type: :integer, desc: 'Run job in parallel', default: 5
        option :image_preview, type: :boolean, desc: 'Upload image preview if present', default: true
        option :preview_prefix, desc: 'Font preview prefix', default: 'preview'
        option :tries, type: :integer, desc: 'Maximum retry count', default: 12

        example [
          'path/to/root # Load fonts at root directory'
        ]

        def call(root:, service:, service_user:, service_password:, parallel:, force:, 
                 specification_file:, image_preview:, preview_prefix:, tries:, **)
          root = File.expand_path(root, Dir.pwd)
                     .tap { |dir| raise LoadError, p unless File.directory?(dir) }

          base_api_uri = File.join(service, '/api/themes/font_families')
                             .tap { |p| puts "Base api path: #{p}" }
          faraday = build_faraday(user: service_user, password: service_password)
          local_font_families = Pathname.new(root)
                                        .children
                                        .select(&:directory?)

          uploads = Parallel.map(local_font_families, in_threads: (parallel || 1).to_i, progress: 'Upserting font families') do |font_family_dir|
            specification_path = File.join(font_family_dir, specification_file)
            next unless File.exist?(specification_path)

            specification = File.read(specification_path).then { |f| JSON.load(f) }

            variants = specification['variants']
                       .filter { |variant| variant.key?('urls') && !variant['urls'].empty? }
                       .map do |variant|
              woff, woff2 = variant.dig('urls')
                                   .slice('woff', 'woff2')
                                   .map { |t, p| [t, File.join(font_family_dir, p)] }.to_h
                                   .map { |t, p| Faraday::UploadIO.new(p, "font/#{t}") }

              image_preview = File.join(font_family_dir, [variant['handle'], 'png'].join('.'))
                                  .then { |p| p if image_preview && File.exist?(p) }
                                  .then { |p| Faraday::UploadIO.new(p, 'image/png') if p }

              preview_woff, preview_woff2 = [woff, woff2]
                                            .map { |io| [io.content_type, prefix_path(io.path, preview_prefix)] }
                                            .to_h
                                            .map { |type, path| Faraday::UploadIO.new(path, type) if File.exist?(path) }
              {
                name: variant['name'],
                handle: variant['handle'],
                family: variant['family'],
                family_default: variant['handle'] == specification['default_variant_handle'],
                style: variant['style'],
                provider: variant['provider'],
                weight: variant['weight']&.to_i,
                fallbacks: variant['fallbacks'],
                woff: woff,
                woff2: woff2,
                preview_woff: preview_woff,
                preview_woff2: preview_woff2,
                image_preview: image_preview
              }.reject { |_, v| v.nil? }
            end

            variants.map do |variant_payload|
              Retriable.retriable(on: HTTP_RETRY_EXCEPTIONS, tries: tries, base_interval: 4) do |try|
                head_response = faraday.get(File.join(base_api_uri, variant_payload[:handle]))
                create_response = if (head_response.status == 404) || (force && head_response.status == 200)
                                    faraday.post(base_api_uri, variant_payload)
                                  else
                                    faraday.get(File.join(base_api_uri, variant_payload[:handle]))
                end.tap { |r| raise DdosProtectionException if r.status == 429 && try < tries }
                
                [variant_payload[:handle], create_response]
              end
            end.to_h
          end

          uploads
            .compact
            .each_with_object({}) { |h, r| h.each { |k, v| (r[k] ||= []) << v } }
            .each(&method(:log_responses))
        end

        private

        def build_faraday(user: nil, password: nil)
          Faraday.new do |builder|
            builder.request :multipart
            builder.request :url_encoded
            builder.adapter :net_http         
            if user && password
              puts "Using basic auth @ #{user}"
              builder.basic_auth(user, password)
            end
          end
        end

        def log_responses(handle, responses)
          responses.map do |response|
            case response.status
            when 201
              "✅ Uploaded font: #{handle}"
            when 200
              "✅ Already uploaded font: #{handle}"
            when 429
              "❎ Upload error: #{handle} (#{response.status} - DDOS protection kicked in)"
            else
              "❎ Upload error: #{handle} (#{response.status})"
            end
          end.map(&method(:puts))
        end

        def prefix_path(path, prefix)
          extname = File.extname(path)
          basename = File.basename(path, extname)
          dirname = File.dirname(path)

          File.join(dirname, [[prefix, basename].join('_'), extname].join)
        end
      end
    end
  end
end
