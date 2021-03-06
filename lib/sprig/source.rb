module Sprig
  class Source

    def initialize(table_name, args = {})
      @table_name = table_name
      @args       = args
    end

    def records
      data[:records] || []
    end

    def options
      data[:options] || {}
    end

    private

    attr_reader :table_name, :args

    def data
      @data ||= begin
        parser_class.new(source).parse.to_hash.with_indifferent_access
      ensure
        source.close
      end
    end

    def source
      @source ||= begin
        source = args.fetch(:source) { default_source }

        unless source.respond_to?(:read) && source.respond_to?(:close)
          raise ArgumentError, 'Data sources must act like an IO.'
        end

        source
      end
    end

    def parser_class
      @parser_class ||= begin
        parser_class = args.fetch(:parser) { default_parser_class }

        unless parser_class.method_defined?(:parse)
          raise ArgumentError, 'Parsers must define #parse.'
        end

        parser_class
      end
    end

    def default_source
      File.open(SourceDeterminer.new(table_name).file)
    end

    def default_parser_class
      ParserDeterminer.new(source).parser
    end


    class SourceDeterminer
      attr_reader :table_name

      def initialize(table_name)
        @table_name = table_name
      end

      def file
        File.new(seed_directory.join(filename))
      end

      private

      class FileNotFoundError < StandardError; end

      def filename
        environment_specific_filename || root_filename || file_not_found
      end

      def root_filename
        detect_file(available_root_files)
      end

      def environment_specific_filename
        name = detect_file(available_environment_files)
        name.prepend("#{Rails.env}/") unless name.nil?
      end

      def detect_file(files)
        files.detect {|name| name =~ /^#{table_name}\./ }
      end

      def available_root_files
        Dir.entries(seed_directory)
      end

      def available_environment_files
        return [] unless File.directory?(seed_environment_directory)
        Dir.entries(seed_environment_directory)
      end

      def file_not_found
        raise FileNotFoundError,
          "No datasource file could be found for '#{table_name}'. Try creating "\
          "#{table_name}.yml, #{table_name}.json, or #{table_name}.csv within "\
          "#{seed_directory}, or define a custom datasource."
      end
    end


    class ParserDeterminer

      def initialize(file)
        @file = file
      end

      def parser
        match = parser_matchers.detect {|p| p[:extension] =~ extension } || unparsable_file
        match[:parser]
      end

      private

      class UnparsableFileError < StandardError; end

      attr_reader :file

      def extension
        File.extname(file)
      end

      def parser_matchers
        [
          {
            extension: /\.y(a)?ml/i,
            parser: Sprig::Parser::Yml
          },
          {
            extension: /\.json/i,
            parser: Sprig::Parser::Json
          },
          {
            extension: /\.csv/i,
            parser: Sprig::Parser::Csv
          }
        ]
      end

      def parsable_formats
        ['YAML', 'JSON', 'CSV']
      end

      def unparsable_file
        raise UnparsableFileError,
          "No parser was found for the file '#{file}'. Provide a custom parser, or "\
          "use a supported data format (#{parsable_formats})."
      end
    end
  end
end
