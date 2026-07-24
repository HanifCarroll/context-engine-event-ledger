class CreateLedgerTables < ActiveRecord::Migration[8.1]
  IMMUTABLE_TABLES = %w[
    source_reports
    ingestion_batches
    event_store_events
    event_store_events_in_streams
  ].freeze

  def up
    create_table :source_reports, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.binary :source_bytes, null: false
      t.string :source_sha256, null: false
      t.string :source_kind, null: false
      t.string :supplied_by_actor_kind, null: false
      t.string :supplied_by_actor_id, null: false
      t.string :privacy, null: false, default: "private"
      t.string :external_locator
      t.string :session_reference
      t.datetime :received_at, null: false, precision: 6
      t.json :evidence_references, null: false, default: []
    end

    add_index :source_reports, :source_sha256

    create_table :ingestion_batches, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :source_report_id, null: false
      t.string :idempotency_key, null: false
      t.string :proposal_digest, null: false
      t.binary :approval_statement, null: false
      t.string :approval_digest, null: false
      t.datetime :approved_at, null: false, precision: 6
      t.string :approval_actor, null: false
      t.string :actor, null: false
      t.string :executor, null: false
      t.datetime :recorded_at, null: false, precision: 6
      t.json :event_ids, null: false, default: []
      t.integer :ledger_position, null: false
      t.string :transaction_digest, null: false
    end

    add_index :ingestion_batches, :idempotency_key, unique: true
    add_index :ingestion_batches, :proposal_digest
    add_foreign_key :ingestion_batches, :source_reports

    create_table :entities, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :kind, null: false
      t.string :display_name, null: false
      t.string :privacy, null: false, default: "private"
      t.string :status, null: false, default: "active"
      t.string :merged_into_id
      t.string :created_by_event_id, null: false
      t.string :updated_by_event_id, null: false
      t.timestamps precision: 6, null: false
    end

    create_table :entity_aliases do |t|
      t.string :entity_id, null: false
      t.string :alias_name, null: false
      t.string :normalized_alias, null: false
      t.string :created_by_event_id, null: false
      t.timestamps precision: 6, null: false
    end

    add_index :entity_aliases, [ :normalized_alias, :entity_id ], unique: true
    add_foreign_key :entity_aliases, :entities

    create_table :event_entity_roles do |t|
      t.string :event_id, null: false
      t.string :entity_id, null: false
      t.string :role, null: false
      t.integer :ordinal, null: false
    end

    add_index :event_entity_roles, [ :event_id, :ordinal ], unique: true
    add_index :event_entity_roles, [ :entity_id, :event_id ]
    add_foreign_key :event_entity_roles, :entities

    create_table :event_effective_states, id: false do |t|
      t.string :event_id, null: false, primary_key: true
      t.string :assertion_status, null: false
      t.string :correction_status, null: false, default: "effective"
      t.string :replacement_event_id
      t.string :updated_by_event_id, null: false
    end

    create_table :projection_checkpoints, id: false do |t|
      t.string :projection_name, null: false, primary_key: true
      t.integer :ledger_position, null: false
      t.string :event_id, null: false
      t.datetime :updated_at, null: false, precision: 6
    end

    IMMUTABLE_TABLES.each { |table| add_immutable_triggers(table) }
  end

  def down
    IMMUTABLE_TABLES.each { |table| remove_immutable_triggers(table) }
    drop_table :projection_checkpoints
    drop_table :event_effective_states
    drop_table :event_entity_roles
    drop_table :entity_aliases
    drop_table :entities
    drop_table :ingestion_batches
    drop_table :source_reports
  end

  private

  def add_immutable_triggers(table)
    execute <<~SQL
      CREATE TRIGGER #{table}_append_only_update
      BEFORE UPDATE ON #{table}
      BEGIN
        SELECT RAISE(ABORT, 'append-only table');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER #{table}_append_only_delete
      BEFORE DELETE ON #{table}
      BEGIN
        SELECT RAISE(ABORT, 'append-only table');
      END;
    SQL
  end

  def remove_immutable_triggers(table)
    execute "DROP TRIGGER IF EXISTS #{table}_append_only_update"
    execute "DROP TRIGGER IF EXISTS #{table}_append_only_delete"
  end
end
