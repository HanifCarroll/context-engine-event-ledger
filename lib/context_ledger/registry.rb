module ContextLedger
  class Registry
    STRING = { "type" => "string", "minLength" => 1 }.freeze
    OBJECT = lambda do |required, properties|
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => required,
        "properties" => properties
      }
    end
    BUILTIN_TYPES = {
      "context.entity_registered.v1" => OBJECT.call(
        %w[id kind display_name],
        { "id" => STRING, "kind" => STRING, "display_name" => STRING }
      ),
      "context.entity_alias_added.v1" => OBJECT.call(
        %w[id alias],
        { "id" => STRING, "alias" => STRING }
      ),
      "context.entity_renamed.v1" => OBJECT.call(
        %w[id display_name],
        { "id" => STRING, "display_name" => STRING }
      ),
      "context.entity_merged.v1" => OBJECT.call(
        %w[source_id target_id],
        { "source_id" => STRING, "target_id" => STRING }
      ),
      "context.entity_retired.v1" => OBJECT.call(
        %w[id],
        { "id" => STRING }
      ),
      "ledger.event_corrected.v1" => OBJECT.call(
        %w[event_id reason],
        { "event_id" => STRING, "reason" => STRING, "replacement_event_id" => STRING }
      ),
      "ledger.event_retracted.v1" => OBJECT.call(
        %w[event_id reason],
        { "event_id" => STRING, "reason" => STRING }
      ),
      "ledger.assertion_status_changed.v1" => OBJECT.call(
        %w[event_id assertion_status reason],
        {
          "event_id" => STRING,
          "assertion_status" => { "enum" => %w[reported externally_verified disputed] },
          "reason" => STRING
        }
      )
    }.freeze

    attr_reader :types, :extensions

    def initialize(extension_paths: configured_paths)
      @types = BUILTIN_TYPES.dup
      @extensions = []
      extension_paths.each { |path| load_extension!(Pathname(path)) }
    end

    def schema_for(type)
      types.fetch(type) { raise Error.new("unknown_event_type", "Event type is not registered", field: "type") }
    end

    private

    def configured_paths
      ENV.fetch("CONTEXT_LEDGER_EXTENSIONS", "").split(File::PATH_SEPARATOR).reject(&:empty?)
    end

    def load_extension!(directory)
      manifest_path = directory.join("manifest.json")
      raise Error.new("extension_manifest_missing", "Extension manifest is missing", path: manifest_path.to_s) unless manifest_path.file?

      manifest = JSON.parse(manifest_path.binread)
      declared = manifest.fetch("files")
      declared.each do |relative, expected|
        file = contained_file(directory, relative)
        actual = file.file? ? Digest::SHA256.file(file).hexdigest : nil
        unless ActiveSupport::SecurityUtils.secure_compare(actual.to_s, expected.to_s)
          raise Error.new("extension_digest_mismatch", "Extension file digest does not match its manifest", path: relative)
        end
      end

      manifest.fetch("schemas", {}).each do |type, relative|
        raise Error.new("duplicate_event_type", "Event type is already registered", type: type) if types.key?(type)

        types[type] = JSON.parse(contained_file(directory, relative).binread)
      end

      if manifest["ruby_entrypoint"]
        entrypoint = contained_file(directory, manifest.fetch("ruby_entrypoint"))
        raise Error.new("extension_entrypoint_undeclared", "Ruby entrypoint is not declared in files") unless declared.key?(manifest["ruby_entrypoint"])
        require entrypoint.to_s
      end

      extensions << { "id" => manifest.fetch("id"), "version" => manifest.fetch("version") }
    rescue JSON::ParserError, KeyError => e
      raise Error.new("extension_manifest_invalid", "Extension manifest is invalid", error: e.message)
    end

    def contained_file(directory, relative)
      candidate = directory.join(relative).cleanpath
      root = directory.realpath
      unless candidate.file? && candidate.realpath.to_s.start_with?("#{root}/")
        raise Error.new("extension_path_invalid", "Extension file must stay inside its configured directory", path: relative)
      end
      candidate
    end
  end
end
