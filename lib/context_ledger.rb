require "base64"
require "digest"
require "fileutils"
require "json"
require "json_schemer"
require "securerandom"
require "time"

module ContextLedger
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details = {})
      @code = code
      @details = details
      super(message)
    end
  end

  module CanonicalJson
    module_function

    def dump(value)
      JSON.generate(sort(value))
    end

    def digest(value)
      Digest::SHA256.hexdigest(dump(value))
    end

    def sort(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.to_h do |key|
          original = value.key?(key) ? value[key] : value[key.to_sym]
          [ key, sort(original) ]
        end
      when Array
        value.map { |item| sort(item) }
      else
        value
      end
    end
  end

  module Paths
    module_function

    def data_dir
      Pathname(ENV.fetch("CONTEXT_LEDGER_DATA_DIR") {
        File.join(Dir.home, ".local", "share", "context-ledger")
      })
    end

    def prepare!
      FileUtils.mkdir_p(data_dir, mode: 0o700)
      File.chmod(0o700, data_dir)
      ENV["LEDGER_DATABASE_PATH"] ||= data_dir.join("ledger.sqlite3").to_s
    end

    def secure_files!
      Dir.glob("#{data_dir}/{*.sqlite3,*.sqlite3-*,backups/*,receipts/*}").each do |path|
        File.chmod(0o600, path) if File.file?(path)
      end
    end
  end
end
