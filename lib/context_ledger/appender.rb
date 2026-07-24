module ContextLedger
  class Appender
    GENESIS_HASH = "0" * 64

    attr_reader :client, :projector

    def initialize(client: Rails.configuration.event_store, projector: Projector.new)
      @client = client
      @projector = projector
    end

    def append(input)
      proposal_input = input.fetch("proposal")
      idempotency_key = proposal_input.fetch("idempotency_key")
      existing = IngestionBatch.find_by(idempotency_key: idempotency_key)
      return retry_result(existing, input) if existing

      validation = Proposal.new.validate(proposal_input)
      normalized = validation.fetch("normalized_proposal")
      supplied_digest = input.fetch("proposal_digest")
      unless ActiveSupport::SecurityUtils.secure_compare(validation.fetch("proposal_digest"), supplied_digest)
        raise Error.new("proposal_digest_mismatch", "The approved proposal digest does not match the normalized proposal")
      end

      approval = input.fetch("approval")
      approval_statement = approval.fetch("statement")
      raise Error.new("approval_missing", "Approval statement is required") if approval_statement.to_s.strip.empty?

      recorded_at = Time.now.utc
      source_id = SecureRandom.uuid
      batch_id = SecureRandom.uuid
      event_ids = normalized.fetch("events").map { |event| event.fetch("event_id") }
      source_bytes = normalized.dig("source", "text").encode(Encoding::UTF_8).b
      approval_bytes = approval_statement.encode(Encoding::UTF_8).b
      last_hash = previous_hash
      stream_versions = normalized.fetch("expected_stream_versions").dup
      ledger_position = nil
      built_events = []

      ActiveRecord::Base.transaction do
        SourceReport.create!(
          id: source_id,
          source_bytes: source_bytes,
          source_sha256: Digest::SHA256.hexdigest(source_bytes),
          source_kind: normalized.dig("source", "kind"),
          supplied_by_actor_kind: normalized.dig("source", "supplied_by", "kind"),
          supplied_by_actor_id: normalized.dig("source", "supplied_by", "id"),
          privacy: normalized.dig("source", "privacy"),
          external_locator: normalized.dig("source", "external_locator"),
          session_reference: normalized.dig("source", "session_reference"),
          received_at: normalized.dig("source", "received_at"),
          evidence_references: normalized.dig("source", "evidence_references")
        )

        normalized.fetch("events").each do |proposed|
          event_data = proposed.merge(
            "source_report_id" => source_id,
            "ingestion_batch_id" => batch_id,
            "recorded_at" => recorded_at.iso8601(6),
            "previous_event_hash" => last_hash
          )
          event_hash = CanonicalJson.digest(event_data)
          event_data["event_hash"] = event_hash
          event = LedgerEvent.new(event_id: proposed.fetch("event_id"), data: event_data)

          append_to_global(event, stream_versions)
          link_secondary_streams(event, source_id, batch_id, stream_versions)
          projector.apply(event)
          built_events << event
          last_hash = event_hash
        end

        ledger_position = client.read.stream("Ledger$all").count - 1
        receipt_body = {
          "batch_id" => batch_id,
          "source_report_id" => source_id,
          "proposal_digest" => supplied_digest,
          "approval_digest" => Digest::SHA256.hexdigest(approval_bytes),
          "event_ids" => event_ids,
          "ledger_position" => ledger_position,
          "recorded_at" => recorded_at.iso8601(6)
        }
        transaction_digest = CanonicalJson.digest(receipt_body)
        IngestionBatch.create!(
          id: batch_id,
          source_report_id: source_id,
          idempotency_key: idempotency_key,
          proposal_digest: supplied_digest,
          approval_statement: approval_bytes,
          approval_digest: receipt_body.fetch("approval_digest"),
          approved_at: Time.iso8601(approval.fetch("timestamp")),
          approval_actor: approval.fetch("actor"),
          actor: input.fetch("actor"),
          executor: input.fetch("executor"),
          recorded_at: recorded_at,
          event_ids: event_ids,
          ledger_position: ledger_position,
          transaction_digest: transaction_digest
        )
      end

      receipt(IngestionBatch.find(batch_id)).merge("idempotent_retry" => false)
    rescue KeyError => e
      raise Error.new("required_field_missing", "A required append field is missing", field: e.key.to_s)
    rescue ArgumentError
      raise Error.new("approval_time_invalid", "Approval timestamp must be ISO 8601")
    ensure
      Paths.secure_files!
    end

    private

    def append_to_global(event, versions)
      expected = versions.fetch("Ledger$all")
      client.append(event, stream_name: "Ledger$all", expected_version: expected == -1 ? :none : expected)
      versions["Ledger$all"] = expected + 1
    end

    def link_secondary_streams(event, source_id, batch_id, versions)
      data = event.data
      streams = [ "Domain$#{data.fetch("domain")}" ] +
        data.fetch("entity_roles").map { |role| "Entity$#{role.fetch("entity_id")}" } +
        [ "SourceReport$#{source_id}", "IngestionBatch$#{batch_id}" ]
      streams.uniq.each do |stream|
        expected = versions.fetch(stream) { client.read.stream(stream).count - 1 }
        client.link(event.event_id, stream_name: stream, expected_version: expected == -1 ? :none : expected)
        versions[stream] = expected + 1
      end
    end

    def previous_hash
      event = client.read.stream("Ledger$all").backward.limit(1).first
      event ? event.data.fetch("event_hash") : GENESIS_HASH
    end

    def retry_result(existing, input)
      supplied_digest = input.fetch("proposal_digest")
      proposal_digest = CanonicalJson.digest(input.fetch("proposal"))
      approval_digest = Digest::SHA256.hexdigest(input.dig("approval", "statement").to_s.b)
      unless ActiveSupport::SecurityUtils.secure_compare(existing.proposal_digest, supplied_digest) &&
          ActiveSupport::SecurityUtils.secure_compare(existing.proposal_digest, proposal_digest) &&
          ActiveSupport::SecurityUtils.secure_compare(existing.approval_digest, approval_digest) &&
          existing.actor == input["actor"] &&
          existing.executor == input["executor"]
        raise Error.new("idempotency_conflict", "Idempotency key was already used with a different proposal")
      end
      receipt(existing).merge("idempotent_retry" => true)
    end

    def receipt(batch)
      {
        "source_report_id" => batch.source_report_id,
        "batch_id" => batch.id,
        "event_ids" => batch.event_ids,
        "ledger_checkpoint" => batch.ledger_position,
        "transaction_digest" => batch.transaction_digest,
        "projection_status" => "current"
      }
    end
  end
end
