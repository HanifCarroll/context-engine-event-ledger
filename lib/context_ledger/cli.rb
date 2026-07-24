module ContextLedger
  class CLI
    COMMANDS = %w[
      doctor validate-proposal append-approved validate-correction append-approved-correction
      validate-assertion-status-change append-approved-assertion-status-change
      validate-entity-change append-approved-entity-change event source-report timeline entity
      entity-history events-by-type events-by-domain events-for-project correction-history
      ledger-status rebuild-projections projection-status verify backup-create backup-list backup-verify
    ].freeze

    def run(argv, input: $stdin, output: $stdout)
      command = argv.shift
      if command.nil? || %w[-h --help help].include?(command)
        write(output, help, ok: true)
        return 0
      end
      raise Error.new("command_unknown", "Unknown command", command: command) unless COMMANDS.include?(command)

      payload = read_input(input)
      result = dispatch(command, payload)
      write(output, result, ok: true)
      0
    rescue Error => e
      write(output, { "error" => { "code" => e.code, "message" => e.message, "details" => e.details } }, ok: false)
      1
    rescue JSON::ParserError
      write(output, { "error" => { "code" => "json_invalid", "message" => "Input must be one JSON object", "details" => {} } }, ok: false)
      1
    rescue StandardError => e
      Rails.logger.error("#{e.class}: #{e.message}") if defined?(Rails)
      write(output, { "error" => { "code" => "internal_error", "message" => "The command failed without exposing private values", "details" => { "class" => e.class.name } } }, ok: false)
      1
    ensure
      Paths.secure_files!
    end

    private

    def dispatch(command, payload)
      case command
      when "doctor"
        {
          "version" => ContextLedger::VERSION,
          "database" => ENV.fetch("LEDGER_DATABASE_PATH"),
          "database_exists" => File.exist?(ENV.fetch("LEDGER_DATABASE_PATH")),
          "extensions" => Registry.new.extensions,
          "network_required" => false
        }
      when "validate-proposal", "validate-correction", "validate-assertion-status-change", "validate-entity-change"
        Proposal.new.validate(payload)
      when "append-approved", "append-approved-correction", "append-approved-assertion-status-change", "append-approved-entity-change"
        Appender.new.append(payload)
      when "event"
        Query.new.event(payload.fetch("event_id"))
      when "source-report"
        Query.new.source_report(payload.fetch("source_report_id"))
      when "timeline"
        Query.new.timeline(payload)
      when "entity"
        Query.new.entity(payload.fetch("entity_id"))
      when "entity-history"
        Query.new.entity_history(payload.fetch("entity_id"))
      when "events-by-type"
        Query.new.timeline("type" => payload.fetch("type"), "limit" => payload.fetch("limit", 100))
      when "events-by-domain"
        Query.new.timeline("domain" => payload.fetch("domain"), "limit" => payload.fetch("limit", 100))
      when "events-for-project"
        Query.new.timeline("entity_id" => payload.fetch("project_id"), "limit" => payload.fetch("limit", 100))
      when "correction-history"
        correction_history(payload.fetch("event_id"))
      when "ledger-status"
        Query.new.status
      when "rebuild-projections"
        Projector.new.rebuild!
      when "projection-status"
        Query.new.status.fetch("projection")
      when "verify"
        Integrity.new.verify
      when "backup-create"
        Backup.new.create
      when "backup-list"
        Backup.new.list
      when "backup-verify"
        Backup.new.verify(payload.fetch("path"))
      end
    rescue KeyError => e
      raise Error.new("required_field_missing", "A required command field is missing", field: e.key.to_s)
    end

    def correction_history(event_id)
      events = Query.new.timeline("limit" => 500).fetch("events").select do |event|
        %w[ledger.event_corrected.v1 ledger.event_retracted.v1].include?(event["type"]) &&
          event.dig("data", "event_id") == event_id
      end
      { "event_id" => event_id, "corrections" => events }
    end

    def read_input(input)
      text = input.read
      return {} if text.strip.empty?
      parsed = JSON.parse(text)
      raise Error.new("json_object_required", "Input must be one JSON object") unless parsed.is_a?(Hash)
      parsed
    end

    def help
      {
        "name" => "context-ledger",
        "usage" => "context-ledger COMMAND < input.json",
        "commands" => COMMANDS
      }
    end

    def write(output, result, ok:)
      output.puts(JSON.generate({ "ok" => ok }.merge(result)))
    end
  end
end
