require "test_helper"
require "context_ledger"
require "context_ledger/registry"
require "context_ledger/proposal"
require "context_ledger/projector"
require "context_ledger/appender"
require "context_ledger/query"
require "context_ledger/integrity"
require "context_ledger/backup"

class ContextLedgerTest < ActiveSupport::TestCase
  test "canonical JSON preserves false and null values" do
    parsed = JSON.parse(ContextLedger::CanonicalJson.dump("false" => false, "null" => nil))
    assert_equal false, parsed.fetch("false")
    assert_nil parsed.fetch("null")
  end

  def proposal(key: SecureRandom.uuid, name: "Example Community", id: "community:example")
    {
      "source" => {
        "text" => "I attended the Example Community meetup.",
        "kind" => "reported_text",
        "privacy" => "private",
        "supplied_by" => { "kind" => "human", "id" => "operator" },
        "received_at" => "2026-07-24T12:00:00Z"
      },
      "idempotency_key" => key,
      "entities" => [
        {
          "id" => id,
          "kind" => "community",
          "display_name" => name,
          "privacy" => "private"
        }
      ],
      "events" => [
        {
          "event_id" => SecureRandom.uuid,
          "type" => "context.entity_registered.v1",
          "domain" => "context",
          "assertion_status" => "reported",
          "time_precision" => "date",
          "occurred_at" => "2026-07-24",
          "privacy" => "private",
          "data" => {
            "id" => id,
            "kind" => "community",
            "display_name" => name
          },
          "entity_roles" => [
            { "entity_id" => id, "role" => "subject" }
          ]
        }
      ]
    }
  end

  def approval
    {
      "statement" => "I approve this exact proposal.",
      "timestamp" => "2026-07-24T12:01:00Z",
      "actor" => "human:operator"
    }
  end

  test "validates, appends, queries, and retries idempotently" do
    validated = ContextLedger::Proposal.new.validate(proposal)
    input = {
      "proposal" => validated.fetch("normalized_proposal"),
      "proposal_digest" => validated.fetch("proposal_digest"),
      "approval" => approval,
      "actor" => "human:operator",
      "executor" => "agent:test"
    }

    first = ContextLedger::Appender.new.append(input)
    second = ContextLedger::Appender.new.append(input)

    assert_equal false, first.fetch("idempotent_retry")
    assert_equal true, second.fetch("idempotent_retry")
    assert_equal first.fetch("batch_id"), second.fetch("batch_id")
    assert_equal 1, Rails.configuration.event_store.read.stream("Ledger$all").count
    assert_equal "Example Community", ContextLedger::Query.new.entity("community:example").fetch("display_name")
    integrity = ContextLedger::Integrity.new.verify
    assert integrity.fetch("ok"), integrity.fetch("issues").inspect
  end

  test "rejects a changed payload under the same idempotency key" do
    raw = proposal
    validated = ContextLedger::Proposal.new.validate(raw)
    input = {
      "proposal" => validated.fetch("normalized_proposal"),
      "proposal_digest" => validated.fetch("proposal_digest"),
      "approval" => approval,
      "actor" => "human:operator",
      "executor" => "agent:test"
    }
    ContextLedger::Appender.new.append(input)

    error = assert_raises(ContextLedger::Error) do
      ContextLedger::Appender.new.append(input.merge("proposal_digest" => "f" * 64))
    end
    assert_equal "idempotency_conflict", error.code
  end

  test "rejects an approved proposal after its expected stream version becomes stale" do
    stale = ContextLedger::Proposal.new.validate(proposal)
    competing = ContextLedger::Proposal.new.validate(
      proposal(name: "Other Community", id: "community:other")
    )
    ContextLedger::Appender.new.append(
      "proposal" => competing.fetch("normalized_proposal"),
      "proposal_digest" => competing.fetch("proposal_digest"),
      "approval" => approval,
      "actor" => "human:operator",
      "executor" => "agent:test"
    )

    error = assert_raises(ContextLedger::Error) do
      ContextLedger::Appender.new.append(
        "proposal" => stale.fetch("normalized_proposal"),
        "proposal_digest" => stale.fetch("proposal_digest"),
        "approval" => approval,
        "actor" => "human:operator",
        "executor" => "agent:test"
      )
    end
    assert_equal "stream_version_stale", error.code
  end

  test "immutable database triggers reject canonical updates and deletes" do
    validated = ContextLedger::Proposal.new.validate(proposal)
    ContextLedger::Appender.new.append(
      "proposal" => validated.fetch("normalized_proposal"),
      "proposal_digest" => validated.fetch("proposal_digest"),
      "approval" => approval,
      "actor" => "human:operator",
      "executor" => "agent:test"
    )

    updates = {
      "source_reports" => "source_sha256='tampered'",
      "ingestion_batches" => "proposal_digest='tampered'",
      "event_store_events" => "event_type='Tampered'",
      "event_store_events_in_streams" => "stream='Tampered'"
    }
    updates.each do |table, assignment|
      assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.connection.execute("UPDATE #{table} SET #{assignment}")
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.connection.execute("DELETE FROM #{table}")
      end
    end
  end

  test "projection rebuild reproduces entity state" do
    validated = ContextLedger::Proposal.new.validate(proposal)
    ContextLedger::Appender.new.append(
      "proposal" => validated.fetch("normalized_proposal"),
      "proposal_digest" => validated.fetch("proposal_digest"),
      "approval" => approval,
      "actor" => "human:operator",
      "executor" => "agent:test"
    )

    before = ContextLedger::Query.new.entity("community:example")
    result = ContextLedger::Projector.new.rebuild!
    after = ContextLedger::Query.new.entity("community:example")

    assert_equal 1, result.fetch("events_applied")
    assert_equal before, after
  end

  test "source and approval digests preserve exact bytes" do
    raw = proposal
    raw["source"]["text"] = "Unicode source ✓\n"
    validated = ContextLedger::Proposal.new.validate(raw)
    result = ContextLedger::Appender.new.append(
      "proposal" => validated.fetch("normalized_proposal"),
      "proposal_digest" => validated.fetch("proposal_digest"),
      "approval" => approval,
      "actor" => "human:operator",
      "executor" => "agent:test"
    )

    source = SourceReport.find(result.fetch("source_report_id"))
    batch = IngestionBatch.find(result.fetch("batch_id"))
    assert_equal Digest::SHA256.hexdigest("Unicode source ✓\n".b), source.source_sha256
    assert_equal Digest::SHA256.hexdigest(approval.fetch("statement").b), batch.approval_digest
  end

  test "correction appends history and changes only effective projection state" do
    initial = ContextLedger::Proposal.new.validate(proposal)
    first = ContextLedger::Appender.new.append(
      "proposal" => initial.fetch("normalized_proposal"),
      "proposal_digest" => initial.fetch("proposal_digest"),
      "approval" => approval,
      "actor" => "human:operator",
      "executor" => "agent:test"
    )
    original_id = first.fetch("event_ids").first

    correction = {
      "source" => {
        "text" => "The original report needs a correction.",
        "kind" => "reported_text",
        "privacy" => "private",
        "supplied_by" => { "kind" => "human", "id" => "operator" },
        "received_at" => "2026-07-24T13:00:00Z"
      },
      "idempotency_key" => SecureRandom.uuid,
      "entities" => [],
      "events" => [
        {
          "type" => "ledger.event_corrected.v1",
          "domain" => "ledger",
          "assertion_status" => "reported",
          "time_precision" => "timestamp",
          "occurred_at" => "2026-07-24T13:00:00Z",
          "privacy" => "private",
          "data" => { "event_id" => original_id, "reason" => "Corrected by the reporter" },
          "entity_roles" => []
        }
      ]
    }
    validated = ContextLedger::Proposal.new.validate(correction)
    ContextLedger::Appender.new.append(
      "proposal" => validated.fetch("normalized_proposal"),
      "proposal_digest" => validated.fetch("proposal_digest"),
      "approval" => approval,
      "actor" => "human:operator",
      "executor" => "agent:test"
    )

    original = ContextLedger::Query.new.event(original_id)
    assert_equal "corrected", original.fetch("correction_status")
    assert_equal 2, Rails.configuration.event_store.read.stream("Ledger$all").count
    assert ContextLedger::Integrity.new.verify.fetch("ok")
  end
end
