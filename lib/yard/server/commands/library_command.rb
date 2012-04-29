require 'thread'

module YARD
  module Server
    module Commands
      class LibraryOptions < CLI::YardocOptions
        def adapter; @command.adapter end
        def library; @command.library end
        def single_library; @command.single_library end
        def serializer; @command.serializer end

        attr_accessor :command
        attr_accessor :frames

        def each(&block)
          super(&block)
          yield(:adapter, adapter)
          yield(:library, library)
          yield(:single_library, single_library)
          yield(:serializer, serializer)
        end
      end

      # This is the base command for all commands that deal directly with libraries.
      # Some commands do not, but most (like {DisplayObjectCommand}) do. If your
      # command deals with libraries directly, subclass this class instead.
      # See {Base} for notes on how to subclass a command.
      #
      # @abstract
      class LibraryCommand < Base
        # @return [LibraryVersion] the object containing library information
        attr_accessor :library

        # @return [LibraryOptions] default options for the library
        attr_accessor :options

        # @return [Serializers::Base] the serializer used to perform file linking
        attr_accessor :serializer

        # @return [Boolean] whether router should route for multiple libraries
        attr_accessor :single_library

        # @return [Boolean] whether to reparse data
        attr_accessor :incremental

        # Needed to synchronize threads in {#setup_yardopts}
        # @private
        @@library_chdir_lock = Mutex.new

        def initialize(opts = {})
          super
          self.serializer = DocServerSerializer.new
        end

        def call(request)
          self.request = request
          self.options = LibraryOptions.new
          self.options.reset_defaults
          self.options.command = self
          setup_library
          self.options.title = "Documentation for #{library.name} " +
            (library.version ? '(' + library.version + ')' : '')
          super
        rescue LibraryNotPreparedError
          not_prepared
        end

        private

        def setup_library
          library.prepare! if request.xhr? && request.query['process']
          load_yardoc
          setup_yardopts
          true
        end

        def setup_yardopts
          @@library_chdir_lock.synchronize do
            Dir.chdir(library.source_path) do
              yardoc = CLI::Yardoc.new
              if incremental
                yardoc.run('-c', '-n', '--no-stats')
              else
                yardoc.parse_arguments
              end
              yardoc.send(:verify_markup_options)
              yardoc.options.delete(:serializer)
              options.update(yardoc.options.to_hash)
            end
          end
        end

        def load_yardoc
          raise LibraryNotPreparedError unless library.yardoc_file
          if Thread.current[:__yard_last_yardoc__] == library.yardoc_file
            log.debug "Reusing yardoc file: #{library.yardoc_file}"
            return
          end
          Registry.clear
          Registry.load_yardoc(library.yardoc_file)
          Thread.current[:__yard_last_yardoc__] = library.yardoc_file
        end

        def not_prepared
          self.caching = false
          options.update(:path => request.path, :template => :doc_server, :type => :processing)
          [202, {'Content-Type' => 'text/html'}, [render]]
        end

        # Hack to load a custom fulldoc template object that does
        # not do any rendering/generation. We need this to access the
        # generate_*_list methods.
        def fulldoc_template
          tplopts = [options.template, :fulldoc, options.format]
          tplclass = Templates::Engine.template(*tplopts)
          obj = Object.new.extend(tplclass)
          class << obj; def init; end end
          obj.class = tplclass
          obj.send(:initialize, options)
          class << obj
            attr_reader :contents
            def asset(file, contents) @contents = contents end
          end
          obj
        end

        # @private
        @@last_yardoc = nil
      end
    end
  end
end
