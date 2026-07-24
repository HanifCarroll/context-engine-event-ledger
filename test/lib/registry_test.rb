require "test_helper"
require "context_ledger"
require "context_ledger/registry"

class RegistryTest < ActiveSupport::TestCase
  test "rejects an extension whose declared digest does not match" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "schema.json"), "{}")
      File.write(
        File.join(directory, "manifest.json"),
        JSON.generate(
          "id" => "example",
          "version" => "1",
          "files" => { "schema.json" => "0" * 64 },
          "schemas" => { "example.event.v1" => "schema.json" }
        )
      )

      error = assert_raises(ContextLedger::Error) do
        ContextLedger::Registry.new(extension_paths: [ directory ])
      end
      assert_equal "extension_digest_mismatch", error.code
    end
  end
end
