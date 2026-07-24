# Backup and recovery

Create and verify backups through named commands:

```sh
context-ledger backup-create
context-ledger backup-list
context-ledger backup-verify < backup-request.json
```

A successful backup check opens the snapshot independently, runs SQLite
integrity, recomputes source, approval, batch, and event-chain digests, checks
append-only triggers and foreign keys, and verifies the projection checkpoint.

Restore is intentionally not an agent command:

1. Stop every Context Ledger writer.
2. Run `backup-verify` against the selected snapshot.
3. Copy the current database and its support files into a separate
   owner-only recovery directory; do not overwrite them in place.
4. Copy the verified snapshot to a new owner-only database path.
5. Point `LEDGER_DATABASE_PATH` at the restored copy and run `verify`.
6. Change the configured live path only after verification passes.

Keep the prior database until the restored copy has passed application
queries and an independent backup. Never merge two database files or replay
events by editing Rails Event Store tables.
