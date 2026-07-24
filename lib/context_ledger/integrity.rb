module ContextLedger
  class Integrity
    IMMUTABLE_TABLES = %w[source_reports ingestion_batches event_store_events event_store_events_in_streams].freeze

    def verify
      issues = []
      verify_sources(issues)
      verify_batches(issues)
      verify_chain(issues)
      verify_triggers(issues)
      connection = ActiveRecord::Base.connection
      foreign_keys = connection.execute("PRAGMA foreign_key_check").to_a
      issues << { "code" => "foreign_key_failure", "rows" => foreign_keys } if foreign_keys.any?
      integrity = connection.select_value("PRAGMA integrity_check")
      issues << { "code" => "sqlite_integrity_failure", "result" => integrity } unless integrity == "ok"
      verify_projection(issues)

      {
        "ok" => issues.empty?,
        "issues" => issues,
        "event_count" => Rails.configuration.event_store.read.stream("Ledger$all").count,
        "sqlite_integrity" => integrity
      }
    end

    private

    def verify_sources(issues)
      SourceReport.find_each do |report|
        actual = Digest::SHA256.hexdigest(report.source_bytes)
        issues << { "code" => "source_digest_mismatch", "source_report_id" => report.id } unless secure_equal?(actual, report.source_sha256)
      end
    end

    def verify_batches(issues)
      IngestionBatch.find_each do |batch|
        body = {
          "batch_id" => batch.id,
          "source_report_id" => batch.source_report_id,
          "proposal_digest" => batch.proposal_digest,
          "approval_digest" => batch.approval_digest,
          "event_ids" => batch.event_ids,
          "ledger_position" => batch.ledger_position,
          "recorded_at" => batch.recorded_at.iso8601(6)
        }
        actual = CanonicalJson.digest(body)
        issues << { "code" => "transaction_digest_mismatch", "batch_id" => batch.id } unless secure_equal?(actual, batch.transaction_digest)
        approval = Digest::SHA256.hexdigest(batch.approval_statement)
        issues << { "code" => "approval_digest_mismatch", "batch_id" => batch.id } unless secure_equal?(approval, batch.approval_digest)
      end
    end

    def verify_chain(issues)
      previous = Appender::GENESIS_HASH
      Rails.configuration.event_store.read.stream("Ledger$all").each.with_index do |event, position|
        data = event.data.deep_dup
        expected = data.delete("event_hash")
        unless data["previous_event_hash"] == previous && secure_equal?(CanonicalJson.digest(data), expected)
          issues << { "code" => "event_hash_mismatch", "event_id" => event.event_id, "position" => position }
        end
        previous = expected
      end
    end

    def verify_triggers(issues)
      names = ActiveRecord::Base.connection.select_values("SELECT name FROM sqlite_master WHERE type='trigger'")
      IMMUTABLE_TABLES.each do |table|
        %w[update delete].each do |operation|
          name = "#{table}_append_only_#{operation}"
          issues << { "code" => "immutable_trigger_missing", "trigger" => name } unless names.include?(name)
        end
      end
    end

    def verify_projection(issues)
      expected = Rails.configuration.event_store.read.stream("Ledger$all").count - 1
      actual = ProjectionCheckpoint.find_by(projection_name: Projector::NAME)&.ledger_position
      return if expected == -1 && actual.nil?
      issues << { "code" => "projection_checkpoint_mismatch", "expected" => expected, "actual" => actual } unless actual == expected
    end

    def secure_equal?(one, two)
      ActiveSupport::SecurityUtils.secure_compare(one.to_s, two.to_s)
    end
  end
end
