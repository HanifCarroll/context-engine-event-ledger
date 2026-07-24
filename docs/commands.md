# Command contract

Run `bin/context-ledger COMMAND < input.json`. Every command reads at most one
JSON object from standard input and writes one JSON object to standard output.

Successful output has `"ok": true`. Errors have `"ok": false` and a stable
`error.code`, safe message, and field-oriented details. Errors never echo
source, identity, event payload, or approval values.

## Discovery and health

- `help`
- `doctor`
- `ledger-status`
- `projection-status`

## Proposal and approved writes

- `validate-proposal`
- `append-approved`
- `validate-correction`
- `append-approved-correction`
- `validate-assertion-status-change`
- `append-approved-assertion-status-change`
- `validate-entity-change`
- `append-approved-entity-change`

Every validate command is read-only. Every append command requires the exact
normalized proposal, its digest, and digest-bound approval evidence.

## Reads

- `event`
- `source-report`
- `timeline`
- `entity`
- `entity-history`
- `events-by-type`
- `events-by-domain`
- `events-for-project`
- `correction-history`

Timeline reads default to 100 events and permit at most 500.

## Maintenance

- `rebuild-projections`
- `verify`
- `backup-create`
- `backup-list`
- `backup-verify`

Restore is an operator procedure rather than an agent command.
