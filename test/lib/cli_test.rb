require "test_helper"
require "context_ledger"
require "context_ledger/version"
require "context_ledger/registry"
require "context_ledger/proposal"
require "context_ledger/projector"
require "context_ledger/appender"
require "context_ledger/query"
require "context_ledger/integrity"
require "context_ledger/backup"
require "context_ledger/cli"

class CLITest < ActiveSupport::TestCase
  test "read commands work before any event has been appended" do
    status_output = StringIO.new
    timeline_output = StringIO.new

    status = ContextLedger::CLI.new.run(
      [ "ledger-status" ],
      input: StringIO.new,
      output: status_output
    )
    timeline = ContextLedger::CLI.new.run(
      [ "timeline" ],
      input: StringIO.new(JSON.generate("limit" => 20)),
      output: timeline_output
    )

    assert_equal 0, status
    assert_equal 0, timeline
    assert JSON.parse(status_output.string).fetch("ok")
    assert JSON.parse(timeline_output.string).fetch("ok")
  end

  test "help is JSON and lists safe named commands" do
    output = StringIO.new
    status = ContextLedger::CLI.new.run([ "--help" ], input: StringIO.new, output: output)
    parsed = JSON.parse(output.string)

    assert_equal 0, status
    assert parsed.fetch("ok")
    assert_includes parsed.fetch("commands"), "validate-proposal"
    assert_includes parsed.fetch("commands"), "append-approved"
    refute_includes parsed.fetch("commands"), "sql"
    refute_includes parsed.fetch("commands"), "eval"
  end

  test "errors do not echo source values" do
    secret_source = "private-source-value"
    output = StringIO.new
    status = ContextLedger::CLI.new.run(
      [ "validate-proposal" ],
      input: StringIO.new(JSON.generate("source" => { "text" => secret_source })),
      output: output
    )

    assert_equal 1, status
    refute_includes output.string, secret_source
  end
end
