# Extensions

Set `CONTEXT_LEDGER_EXTENSIONS` to one or more absolute extension directories
separated by the platform path separator.

Each directory contains `manifest.json`. The manifest declares:

- a stable extension `id` and `version`;
- every loaded file and its SHA-256 digest;
- logical event types and their JSON Schema files;
- an optional trusted Ruby entrypoint.

The application refuses missing, undeclared, or digest-mismatched files.
Declarative schemas can add event data contracts without application changes.
A trusted Ruby entrypoint may register private validators or projection
handlers through the documented application API as it develops.

Ruby entrypoints execute with the application's local authority. They are not
sandboxed and must never be downloaded or enabled automatically.
