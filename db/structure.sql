CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "event_store_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "event_id" varchar(36) NOT NULL, "event_type" varchar NOT NULL, "metadata" blob, "data" blob NOT NULL, "created_at" datetime(6) NOT NULL, "valid_at" datetime(6));
CREATE UNIQUE INDEX "index_event_store_events_on_event_id" ON "event_store_events" ("event_id") /*application='ContextLedgerApp'*/;
CREATE INDEX "index_event_store_events_on_event_type" ON "event_store_events" ("event_type") /*application='ContextLedgerApp'*/;
CREATE INDEX "index_event_store_events_on_created_at" ON "event_store_events" ("created_at") /*application='ContextLedgerApp'*/;
CREATE INDEX "index_event_store_events_on_valid_at" ON "event_store_events" ("valid_at") /*application='ContextLedgerApp'*/;
CREATE TABLE "event_store_events_in_streams" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "stream" varchar NOT NULL, "position" integer DEFAULT NULL, "event_id" varchar(36) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c8d52b5857"
FOREIGN KEY ("event_id")
  REFERENCES "event_store_events" ("event_id")
);
CREATE INDEX "index_event_store_events_in_streams_on_event_id" ON "event_store_events_in_streams" ("event_id") /*application='ContextLedgerApp'*/;
CREATE INDEX "index_event_store_events_in_streams_on_created_at" ON "event_store_events_in_streams" ("created_at") /*application='ContextLedgerApp'*/;
CREATE UNIQUE INDEX "index_event_store_events_in_streams_on_stream_and_position" ON "event_store_events_in_streams" ("stream", "position") /*application='ContextLedgerApp'*/;
CREATE UNIQUE INDEX "index_event_store_events_in_streams_on_stream_and_event_id" ON "event_store_events_in_streams" ("stream", "event_id") /*application='ContextLedgerApp'*/;
CREATE TABLE "source_reports" ("id" varchar NOT NULL PRIMARY KEY, "source_bytes" blob NOT NULL, "source_sha256" varchar NOT NULL, "source_kind" varchar NOT NULL, "supplied_by_actor_kind" varchar NOT NULL, "supplied_by_actor_id" varchar NOT NULL, "privacy" varchar DEFAULT 'private' NOT NULL, "external_locator" varchar, "session_reference" varchar, "received_at" datetime(6) NOT NULL, "evidence_references" json DEFAULT '[]' NOT NULL);
CREATE INDEX "index_source_reports_on_source_sha256" ON "source_reports" ("source_sha256") /*application='ContextLedgerApp'*/;
CREATE TABLE "ingestion_batches" ("id" varchar NOT NULL PRIMARY KEY, "source_report_id" varchar NOT NULL, "idempotency_key" varchar NOT NULL, "proposal_digest" varchar NOT NULL, "approval_statement" blob NOT NULL, "approval_digest" varchar NOT NULL, "approved_at" datetime(6) NOT NULL, "approval_actor" varchar NOT NULL, "actor" varchar NOT NULL, "executor" varchar NOT NULL, "recorded_at" datetime(6) NOT NULL, "event_ids" json DEFAULT '[]' NOT NULL, "ledger_position" integer NOT NULL, "transaction_digest" varchar NOT NULL, CONSTRAINT "fk_rails_093f5e5519"
FOREIGN KEY ("source_report_id")
  REFERENCES "source_reports" ("id")
);
CREATE UNIQUE INDEX "index_ingestion_batches_on_idempotency_key" ON "ingestion_batches" ("idempotency_key") /*application='ContextLedgerApp'*/;
CREATE INDEX "index_ingestion_batches_on_proposal_digest" ON "ingestion_batches" ("proposal_digest") /*application='ContextLedgerApp'*/;
CREATE TABLE "entities" ("id" varchar NOT NULL PRIMARY KEY, "kind" varchar NOT NULL, "display_name" varchar NOT NULL, "privacy" varchar DEFAULT 'private' NOT NULL, "status" varchar DEFAULT 'active' NOT NULL, "merged_into_id" varchar, "created_by_event_id" varchar NOT NULL, "updated_by_event_id" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "entity_aliases" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "entity_id" varchar NOT NULL, "alias_name" varchar NOT NULL, "normalized_alias" varchar NOT NULL, "created_by_event_id" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_d1a934bbb3"
FOREIGN KEY ("entity_id")
  REFERENCES "entities" ("id")
);
CREATE UNIQUE INDEX "index_entity_aliases_on_normalized_alias_and_entity_id" ON "entity_aliases" ("normalized_alias", "entity_id") /*application='ContextLedgerApp'*/;
CREATE TABLE "event_entity_roles" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "event_id" varchar NOT NULL, "entity_id" varchar NOT NULL, "role" varchar NOT NULL, "ordinal" integer NOT NULL, CONSTRAINT "fk_rails_b935c42771"
FOREIGN KEY ("entity_id")
  REFERENCES "entities" ("id")
);
CREATE UNIQUE INDEX "index_event_entity_roles_on_event_id_and_ordinal" ON "event_entity_roles" ("event_id", "ordinal") /*application='ContextLedgerApp'*/;
CREATE INDEX "index_event_entity_roles_on_entity_id_and_event_id" ON "event_entity_roles" ("entity_id", "event_id") /*application='ContextLedgerApp'*/;
CREATE TABLE "event_effective_states" ("event_id" varchar NOT NULL PRIMARY KEY, "assertion_status" varchar NOT NULL, "correction_status" varchar DEFAULT 'effective' NOT NULL, "replacement_event_id" varchar, "updated_by_event_id" varchar NOT NULL);
CREATE TABLE "projection_checkpoints" ("projection_name" varchar NOT NULL PRIMARY KEY, "ledger_position" integer NOT NULL, "event_id" varchar NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TRIGGER source_reports_append_only_update
BEFORE UPDATE ON source_reports
BEGIN
  SELECT RAISE(ABORT, 'append-only table');
END;
CREATE TRIGGER source_reports_append_only_delete
BEFORE DELETE ON source_reports
BEGIN
  SELECT RAISE(ABORT, 'append-only table');
END;
CREATE TRIGGER ingestion_batches_append_only_update
BEFORE UPDATE ON ingestion_batches
BEGIN
  SELECT RAISE(ABORT, 'append-only table');
END;
CREATE TRIGGER ingestion_batches_append_only_delete
BEFORE DELETE ON ingestion_batches
BEGIN
  SELECT RAISE(ABORT, 'append-only table');
END;
CREATE TRIGGER event_store_events_append_only_update
BEFORE UPDATE ON event_store_events
BEGIN
  SELECT RAISE(ABORT, 'append-only table');
END;
CREATE TRIGGER event_store_events_append_only_delete
BEFORE DELETE ON event_store_events
BEGIN
  SELECT RAISE(ABORT, 'append-only table');
END;
CREATE TRIGGER event_store_events_in_streams_append_only_update
BEFORE UPDATE ON event_store_events_in_streams
BEGIN
  SELECT RAISE(ABORT, 'append-only table');
END;
CREATE TRIGGER event_store_events_in_streams_append_only_delete
BEFORE DELETE ON event_store_events_in_streams
BEGIN
  SELECT RAISE(ABORT, 'append-only table');
END;
INSERT INTO "schema_migrations" (version) VALUES
('20260724133717'),
('20260724103717');
