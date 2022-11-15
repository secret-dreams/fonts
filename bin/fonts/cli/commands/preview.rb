# frozen_string_literal: true

require 'dry/cli/command'
require 'mini_magick'
require 'parallel'
require 'open3'

module Fonts
  module CLI
    module Commands
      class Preview < Dry::CLI::Command
        PREVIEW_TEXT      = 'ABCDEFGHIJKLM\nNOPQRSTUVWXYZ\nabcdefghijklm\nnopqrstuvwxyz\n1234567890\n!@$\%(){}[]'
        PREVIEW_POSITION  = '+0+0'
        PREVIEW_SIZE      = '532x365'
        PREVIEW_FONT_SIZE = 38
        PREVIEW_BG_COLOR  = '#ffffff'
        PREVIEW_FG_COLOR  = '#000000'

        argument :root, required: true, desc: 'Root directory from which fonts will be readed'

        option :output, desc: 'JSON sourcefile for fonts', default: nil
        option :format, desc: 'Accepted font format', default: 'woff'
        option :text, desc: 'Text used for preview', default: PREVIEW_TEXT
        option :specification_file, desc: 'Name of file that describes font family', default: 'font_family.json'
        option :preview_prefix, desc: 'Font preview prefix', default: 'preview'
        option :parallel, desc: 'Run job in parallel', default: 5
        option :images, type: :boolean, desc: 'Generate preview images', default: true
        option :fonts, type: :boolean, desc: 'Generate preview fonts', default: true

        def call(root:, format:, text:, parallel:, specification_file:, preview_prefix:, output: nil, images: true, fonts: true, **)
          root = File.expand_path(root, Dir.pwd)
                     .tap { |dir| raise LoadError, p unless File.directory?(dir) }

          files = Dir["#{root}/**/*.#{format}"]
                  .reject { |path| File.basename(path, ".#{format}").start_with?(preview_prefix + '_') }
          previews = Parallel.map(files, in_threads: (parallel || 1).to_i, progress: 'Generating font previews') do |path|
            dirname  = (output || File.dirname(path))
                       .then { |dir| File.expand_path(dir, Dir.pwd) }
                       .tap { |dir| FileUtils.mkdir_p(dir) unless File.directory?(dir) }
                       .tap { |dir| raise LoadError, p unless File.directory?(dir) }
            basename = File.basename(path, ".#{format}")
            font_family_name = File.join(dirname, specification_file)
                                   .then { |path| JSON.load(File.read(path)) if File.exist?(path) }
                                   .then { |json| json['name'] if !json.nil? && json.key?('name') }
                                   .then { |family_name| family_name.nil? ? basename : family_name }

            font_preview_path = if fonts
                                  %w[woff woff2]
                                    .map { |format| [format, File.join(dirname, [[preview_prefix, basename].join('_'), format].join('.'))] }
                                    .to_h
                                    .map { |format, output| font_preview(path, font_family_name, output, format) }
                                else
                                  []
            end

            image_preview_path = if images
                                   File.join(dirname, [basename, 'png'].join('.'))
                                       .then { |output| image_preview(path, text, output) }
            end

            [path, { image: image_preview_path, font: font_preview_path }]
          end.to_h

          previews.each do |path, output|
            if output[:image].nil? && output[:font].compact.empty?
              puts "❎ Ignored #{path} font and image preview"
            else
              puts "✅ Saved #{path} font preview: #{output.inspect}"
            end
          end
        end

        private

        def image_preview(path, text, output)
          return if File.exist?(output)
          return unless File.exist?(path)

          MiniMagick::Tool::Convert.new do |convert|
            convert.merge! ['-size', PREVIEW_SIZE, ['xc', PREVIEW_BG_COLOR].join(':')]
            convert.merge! ['-gravity', 'center']
            convert.merge! ['-font', path]
            convert.merge! ['-pointsize', PREVIEW_FONT_SIZE]
            convert.merge! ['-fill', PREVIEW_FG_COLOR]
            convert.merge! ['-annotate', '+0+0', (text || PREVIEW_TEXT)]

            convert << '-flatten'
            convert << output
          end

          output
        end

        def font_preview(path, font_family, output, format)
          return if File.exist?(output)
          return unless File.exist?(path)

          unicode_chars = font_family
                          .unpack('U*')
                          .map { |unicode| ['U+', unicode.to_s(16).rjust(4, '0')].join }
                          .uniq

          args = ['pyftsubset', path, "--unicodes=#{unicode_chars.join(',')}",
                  "--flavor=#{format}", "--output-file=#{output}"]
          args.push('--with-zopfli') if format == 'woff'

          # FileUtils.rm_f(output) if File.exist?(output)
          Open3.popen3(*args) do |_stdout, _stderr, _status, _thread|
            # dummy block
          end

          output
        end
      end
    end
  end
end
