# Context Ledger

Context Ledger is a local-first, append-only event ledger for AI agents. An
agent can normalize a human report into typed events, show the exact proposal
for approval, and append it only when the caller supplies approval evidence
bound to that proposal.

The application preserves exact source text, records corrections as new
events, keeps identity resolution explicit, and rebuilds current views from
canonical history. It runs locally with Rails, SQLite, and Rails Event Store;
it does not require a server or hosted account.

## Status

Version 0.1 is an early public foundation. The command interface and database
schema may change before 1.0, but accepted event history is never rewritten by
application commands.

## Requirements

- Ruby 4.0 or a compatible current Ruby
- SQLite 3
- Bundler

## Setup

```sh
bundle install
CONTEXT_LEDGER_DATA_DIR="$PWD/tmp/example-ledger" bin/context-ledger-setup
CONTEXT_LEDGER_DATA_DIR="$PWD/tmp/example-ledger" bin/context-ledger doctor
```

The default data directory is `~/.local/share/context-ledger`. Context Ledger
creates it with owner-only permissions. Set `CONTEXT_LEDGER_DATA_DIR` to keep
an installation elsewhere.

Run `bin/install-local` to place `context-ledger` on `~/.local/bin`. Set
`CONTEXT_LEDGER_BIN_DIR` when a different installation directory is needed.

Run `bin/fictional-smoke` to exercise read-only validation, approved append,
idempotent retry, timeline query, projection rebuild, and independent backup
verification in a temporary database.

## Approval flow

```sh
context-ledger validate-proposal < proposal.json
context-ledger append-approved < approved.json
context-ledger verify
```

`validate-proposal` does not write. Its normalized proposal and digest must be
shown to the human by the calling integration. `append-approved` verifies the
digest again and preserves the exact approval statement. The core proves that
the stored statement is bound to the proposal; the calling integration is
responsible for proving that the named human supplied it.

See [Command contract](docs/commands.md), [Architecture](docs/architecture.md),
[Extensions](docs/extensions.md), [Backup and recovery](docs/recovery.md), and
[Security](SECURITY.md).

## What this is not

Context Ledger is not a CRM, journal UI, activity tracker, task manager, or
autonomous memory system. It supplies the event, provenance, approval,
correction, query, and projection layer those systems can build on.

## License

[MIT](LICENSE)
