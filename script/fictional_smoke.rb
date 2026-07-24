require "tmpdir"
require "context_ledger"
require "context_ledger/registry"
require "context_ledger/proposal"
require "context_ledger/projector"
require "context_ledger/appender"
require "context_ledger/query"
require "context_ledger/integrity"
require "context_ledger/backup"

proposal_path = Rails.root.join("examples/fictional-proposal.json")
proposal = JSON.parse(proposal_path.binread)
validation = ContextLedger::Proposal.new.validate(proposal)
raise "proposal wrote state" unless SourceReport.count.zero?

input = {
  "proposal" => validation.fetch("normalized_proposal"),
  "proposal_digest" => validation.fetch("proposal_digest"),
  "approval" => {
    "statement" => "I approve this fictional example.",
    "timestamp" => "2026-07-24T12:01:00Z",
    "actor" => "human:example"
  },
  "actor" => "human:example",
  "executor" => "agent:fictional-smoke"
}

first = ContextLedger::Appender.new.append(input)
retry_result = ContextLedger::Appender.new.append(input)
raise "retry added data" unless retry_result.fetch("idempotent_retry") && IngestionBatch.count == 1

timeline = ContextLedger::Query.new.timeline("entity_id" => "community:example")
raise "timeline mismatch" unless timeline.fetch("events").length == 2
raise "integrity failed" unless ContextLedger::Integrity.new.verify.fetch("ok")

before = ContextLedger::Query.new.entity("community:example")
ContextLedger::Projector.new.rebuild!
after = ContextLedger::Query.new.entity("community:example")
raise "projection mismatch" unless before == after

backup = ContextLedger::Backup.new.create
raise "backup failed" unless backup.fetch("ok")

puts JSON.generate(
  "ok" => true,
  "batch_id" => first.fetch("batch_id"),
  "event_count" => timeline.fetch("events").length,
  "idempotent_retry" => true,
  "projection_rebuilt" => true,
  "backup_verified" => true
)
