require "sqlite3"
require "open3"

module ContextLedger
  class Backup
    def create
      directory = Paths.data_dir.join("backups")
      FileUtils.mkdir_p(directory, mode: 0o700)
      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6NZ")
      path = directory.join("ledger-#{timestamp}.sqlite3")
      quoted = ActiveRecord::Base.connection.quote(path.to_s)
      ActiveRecord::Base.connection.execute("VACUUM INTO #{quoted}")
      File.chmod(0o600, path)
      verify_path(path).merge("path" => path.to_s)
    end

    def list
      { "backups" => Dir.glob(Paths.data_dir.join("backups", "*.sqlite3")).sort.map { |path| metadata(Pathname(path)) } }
    end

    def verify(path)
      candidate = Pathname(path).cleanpath
      root = Paths.data_dir.join("backups").realpath
      unless candidate.file? && candidate.realpath.to_s.start_with?("#{root}/")
        raise Error.new("backup_path_invalid", "Backup must be an existing file in the configured backup directory")
      end
      verify_path(candidate).merge("path" => candidate.to_s)
    end

    private

    def verify_path(path)
      database = SQLite3::Database.new(path.to_s, readonly: true)
      integrity = database.get_first_value("PRAGMA integrity_check")
      ledger = verify_ledger(path)
      {
        "ok" => integrity == "ok" && ledger.fetch("ok"),
        "sqlite_integrity" => integrity,
        "ledger_integrity" => ledger,
        "sha256" => Digest::SHA256.file(path).hexdigest,
        "bytes" => path.size
      }
    ensure
      database&.close
    end

    def metadata(path)
      { "path" => path.to_s, "bytes" => path.size, "sha256" => Digest::SHA256.file(path).hexdigest }
    end

    def verify_ledger(path)
      environment = {
        "LEDGER_DATABASE_PATH" => path.to_s,
        "CONTEXT_LEDGER_DATA_DIR" => Paths.data_dir.to_s,
        "CONTEXT_LEDGER_EXTENSIONS" => ENV.fetch("CONTEXT_LEDGER_EXTENSIONS", ""),
        "RAILS_ENV" => ENV.fetch("RAILS_ENV", "development")
      }
      stdout, _stderr, status = Open3.capture3(
        environment,
        Rails.root.join("bin/context-ledger").to_s,
        "verify",
        stdin_data: "{}"
      )
      parsed = JSON.parse(stdout)
      return parsed if status.success? && parsed.is_a?(Hash)

      { "ok" => false, "issues" => [ { "code" => "backup_ledger_verification_failed" } ] }
    rescue JSON::ParserError
      { "ok" => false, "issues" => [ { "code" => "backup_ledger_verification_invalid" } ] }
    end
  end
end
