# Security

Do not open a public issue for a suspected vulnerability involving private
data exposure, append-only bypass, approval bypass, arbitrary code execution,
or path traversal. Use GitHub's private vulnerability reporting feature for
this repository.

The default installation is local and single-user. The command interface does
not require a web server. Data directories, databases, write-ahead logs,
receipts, and backups must remain owner-readable and owner-writable only.
Source text, event payloads, identities, and approval statements must not
appear in logs, shell arguments, or exception output.

Extension Ruby entrypoints are trusted local code. Context Ledger verifies
their declared file digests, but it does not sandbox them. Never load an
extension from an untrusted directory or remote source.

Backup encryption is outside version 0.1. Unencrypted backups must remain on
owner-only local storage or an independently encrypted volume.
