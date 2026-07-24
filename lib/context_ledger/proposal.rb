module ContextLedger
  class Proposal
    ASSERTION_STATES = %w[reported externally_verified disputed].freeze
    PRIVACY_STATES = %w[private restricted public].freeze
    TIME_PRECISIONS = %w[timestamp date range unknown].freeze
    ENTITY_KINDS = %w[person community event_series organization project tool place].freeze
    ROLES = %w[actor subject origin venue participant affected result evidence_owner].freeze

    attr_reader :registry

    def initialize(registry: Registry.new)
      @registry = registry
    end

    def validate(input)
      source = input.fetch("source")
      text = source.fetch("text")
      raise Error.new("source_invalid", "Source text must be valid UTF-8") unless text.is_a?(String) && text.valid_encoding?

      entities = Array(input["entities"]).map { |entity| normalize_entity(entity) }
      existing_entity_ids = Entity.where(id: entities.map { |entity| entity["id"] }).pluck(:id)
      duplicate_ids = entities.map { |entity| entity.fetch("id") } & existing_entity_ids
      raise Error.new("entity_already_exists", "Proposed entity already exists", entity_ids: duplicate_ids) if duplicate_ids.any?
      entity_ids = entities.map { |entity| entity.fetch("id") } | Entity.pluck(:id)
      events = Array(input.fetch("events")).map.with_index { |event, index| normalize_event(event, index, entity_ids) }
      raise Error.new("events_empty", "At least one event is required") if events.empty?
      validate_entity_registrations!(entities, events)

      streams = projected_streams(events)
      expected_versions = streams.to_h { |stream| [ stream, stream_version(stream) ] }
      supplied_versions = input.fetch("expected_stream_versions", {})
      unless supplied_versions.empty? || supplied_versions == expected_versions
        raise Error.new("stream_version_stale", "Expected stream versions no longer match", current: expected_versions)
      end

      normalized = {
        "source" => {
          "text" => text,
          "kind" => source.fetch("kind", "reported_text"),
          "privacy" => source.fetch("privacy", "private"),
          "supplied_by" => source.fetch("supplied_by", { "kind" => "human", "id" => "operator" }),
          "received_at" => normalize_time(source["received_at"] || Time.now.utc.iso8601(6)),
          "external_locator" => source["external_locator"],
          "session_reference" => source["session_reference"],
          "evidence_references" => Array(source["evidence_references"])
        },
        "idempotency_key" => input.fetch("idempotency_key"),
        "entities" => entities.sort_by { |entity| entity.fetch("id") },
        "events" => events,
        "expected_stream_versions" => expected_versions
      }
      normalized["source"]["privacy"].then { |value| check_enum!("source.privacy", value, PRIVACY_STATES) }

      {
        "normalized_proposal" => normalized,
        "proposal_digest" => CanonicalJson.digest(normalized),
        "extensions" => registry.extensions,
        "projected_effects" => {
          "new_entities" => entities.map { |entity| entity.fetch("id") },
          "event_count" => events.length,
          "streams" => streams
        },
        "warnings" => [],
        "blockers" => []
      }
    rescue KeyError => e
      raise Error.new("required_field_missing", "A required proposal field is missing", field: e.key.to_s)
    end

    private

    def normalize_entity(entity)
      kind = entity.fetch("kind")
      check_enum!("entity.kind", kind, ENTITY_KINDS)
      {
        "id" => entity.fetch("id"),
        "kind" => kind,
        "display_name" => entity.fetch("display_name"),
        "privacy" => entity.fetch("privacy", "private"),
        "aliases" => Array(entity["aliases"]).uniq.sort
      }
    end

    def normalize_event(event, index, entity_ids)
      type = event.fetch("type")
      schema = registry.schema_for(type)
      data = event.fetch("data", {})
      errors = JSONSchemer.schema(schema).validate(data).to_a
      raise Error.new("event_schema_invalid", "Event data does not match its registered schema", index: index, errors: errors) if errors.any?

      assertion = event.fetch("assertion_status", "reported")
      precision = event.fetch("time_precision", "unknown")
      privacy = event.fetch("privacy", "private")
      check_enum!("events[#{index}].assertion_status", assertion, ASSERTION_STATES)
      check_enum!("events[#{index}].time_precision", precision, TIME_PRECISIONS)
      check_enum!("events[#{index}].privacy", privacy, PRIVACY_STATES)
      roles = Array(event["entity_roles"]).map.with_index do |role, ordinal|
        check_enum!("events[#{index}].entity_roles[#{ordinal}].role", role.fetch("role"), ROLES)
        unless entity_ids.include?(role.fetch("entity_id"))
          raise Error.new("entity_unresolved", "Entity role references an unknown entity", entity_id: role["entity_id"])
        end
        { "entity_id" => role.fetch("entity_id"), "role" => role.fetch("role"), "ordinal" => ordinal }
      end

      {
        "event_id" => event["event_id"] || SecureRandom.uuid,
        "type" => type,
        "domain" => event.fetch("domain"),
        "data" => data,
        "assertion_status" => assertion,
        "occurred_at" => event["occurred_at"],
        "time_precision" => precision,
        "privacy" => privacy,
        "entity_roles" => roles
      }
    end

    def projected_streams(events)
      events.flat_map do |event|
        [ "Ledger$all", "Domain$#{event.fetch("domain")}" ] +
          event.fetch("entity_roles").map { |role| "Entity$#{role.fetch("entity_id")}" }
      end.uniq.sort
    end

    def validate_entity_registrations!(entities, events)
      registrations = events.select { |event| event["type"] == "context.entity_registered.v1" }
      alias_events = events.select { |event| event["type"] == "context.entity_alias_added.v1" }
      registered_ids = registrations.map { |event| event.dig("data", "id") }
      missing = entities.map { |entity| entity.fetch("id") } - registered_ids
      raise Error.new("entity_registration_missing", "Every new entity requires a registration event", entity_ids: missing) if missing.any?

      entities.each do |entity|
        event = registrations.find { |candidate| candidate.dig("data", "id") == entity.fetch("id") }
        next if event && event.dig("data", "kind") == entity.fetch("kind") &&
          event.dig("data", "display_name") == entity.fetch("display_name")

        raise Error.new("entity_registration_mismatch", "Entity registration data must match the proposed entity", entity_id: entity.fetch("id"))
      end

      entities.each do |entity|
        recorded_aliases = alias_events.filter_map do |event|
          event.dig("data", "alias") if event.dig("data", "id") == entity.fetch("id")
        end.sort
        next if recorded_aliases == entity.fetch("aliases")

        raise Error.new("entity_alias_mismatch", "Every proposed alias requires a matching alias event", entity_id: entity.fetch("id"))
      end
    end

    def stream_version(stream)
      Rails.configuration.event_store.read.stream(stream).count - 1
    end

    def normalize_time(value)
      Time.iso8601(value).utc.iso8601(6)
    rescue ArgumentError
      raise Error.new("time_invalid", "Timestamp must be ISO 8601")
    end

    def check_enum!(field, value, allowed)
      return if allowed.include?(value)

      raise Error.new("enum_invalid", "Field has an unsupported value", field: field, allowed: allowed)
    end
  end
end
