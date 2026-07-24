# Architecture

Context Ledger has four boundaries:

1. **Exact sources** preserve the UTF-8 bytes supplied to a proposal and their
   SHA-256 digest.
2. **Canonical events** live in Rails Event Store. `Ledger$all` supplies the
   one hash-chain order; domain, entity, source, and batch streams are links.
3. **Immutable batch receipts** bind event IDs, source, normalized proposal,
   approval evidence, ledger position, and transaction digest.
4. **Projections** provide entities, aliases, roles, effective assertion and
   correction state, and checkpoints. They may be deleted and rebuilt.

SQLite triggers reject updates and deletes against sources, batches, events,
and stream links. Public commands expose no generic persistence operation.

## Approval boundary

Validation computes expected stream versions and a canonical proposal digest.
Appending repeats validation, checks the digest, preserves approval evidence,
and writes one transaction. The application can verify the binding but cannot
independently know whether a human supplied the approval statement. The
calling agent integration owns that interaction.

## Integrity chain

The first event uses 64 zeroes as its predecessor. Every later hash covers the
previous hash and the complete logical event data. Multi-event batches retain
their approved order. SQLite's write lock plus Rails Event Store expected
versions rejects competing stale appends.

## Public and private code

The repository contains storage, generic lifecycle events, command contracts,
and a manifest-based extension interface. A user's domain schemas,
identities, source mappings, and application integration stay in a private
extension bundle.
