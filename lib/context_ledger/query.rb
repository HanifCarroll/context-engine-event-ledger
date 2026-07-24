module ContextLedger
  class Query
    attr_reader :client

    def initialize(client: Rails.configuration.event_store)
      @client = client
    end

    def event(id)
      item = client.read.event(id)
      serialize(item)
    rescue RubyEventStore::EventNotFound
      raise Error.new("event_not_found", "Event was not found", event_id: id)
    end

    def source_report(id)
      report = SourceReport.find_by(id: id)
      raise Error.new("source_report_not_found", "Source report was not found", source_report_id: id) unless report

      bytes = report.source_bytes
      {
        "id" => report.id,
        "source_kind" => report.source_kind,
        "source_sha256" => report.source_sha256,
        "source_text" => bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding? ? bytes.dup.force_encoding(Encoding::UTF_8) : nil,
        "source_base64" => Base64.strict_encode64(bytes),
        "privacy" => report.privacy,
        "received_at" => report.received_at.iso8601(6),
        "external_locator" => report.external_locator,
        "evidence_references" => report.evidence_references
      }
    end

    def timeline(input = {})
      events = client.read.stream("Ledger$all").to_a
      events.select! { |event| event.data["domain"] == input["domain"] } if input["domain"]
      events.select! { |event| event.data["type"] == input["type"] } if input["type"]
      if input["entity_id"]
        allowed = EventEntityRole.where(entity_id: input["entity_id"]).pluck(:event_id)
        events.select! { |event| allowed.include?(event.event_id) }
      end
      limit = Integer(input.fetch("limit", 100))
      raise Error.new("limit_invalid", "Limit must be between 1 and 500") unless limit.between?(1, 500)

      { "events" => events.last(limit).map { |event| serialize(event) }, "count" => events.length }
    end

    def entity(id)
      item = Entity.find_by(id: id)
      raise Error.new("entity_not_found", "Entity was not found", entity_id: id) unless item

      {
        "id" => item.id,
        "kind" => item.kind,
        "display_name" => item.display_name,
        "privacy" => item.privacy,
        "status" => item.status,
        "merged_into_id" => item.merged_into_id,
        "aliases" => item.entity_aliases.order(:id).pluck(:alias_name)
      }
    end

    def entity_history(id)
      entity(id)
      timeline("entity_id" => id, "limit" => 500)
    end

    def status
      {
        "event_count" => client.read.stream("Ledger$all").count,
        "source_report_count" => SourceReport.count,
        "batch_count" => IngestionBatch.count,
        "entity_count" => Entity.count,
        "projection" => ProjectionCheckpoint.find_by(projection_name: Projector::NAME)&.attributes
      }
    end

    private

    def serialize(event)
      state = EventEffectiveState.find_by(event_id: event.event_id)
      {
        "event_id" => event.event_id,
        "type" => event.data.fetch("type"),
        "domain" => event.data.fetch("domain"),
        "data" => event.data.fetch("data"),
        "occurred_at" => event.data["occurred_at"],
        "time_precision" => event.data.fetch("time_precision"),
        "recorded_at" => event.data.fetch("recorded_at"),
        "assertion_status" => state&.assertion_status || event.data.fetch("assertion_status"),
        "correction_status" => state&.correction_status || "effective",
        "replacement_event_id" => state&.replacement_event_id,
        "privacy" => event.data.fetch("privacy"),
        "source_report_id" => event.data.fetch("source_report_id"),
        "ingestion_batch_id" => event.data.fetch("ingestion_batch_id"),
        "entity_roles" => event.data.fetch("entity_roles"),
        "event_hash" => event.data.fetch("event_hash")
      }
    end
  end
end
