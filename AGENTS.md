# Repository instructions

Keep Context Ledger local-first, append-only, agent-neutral, and safe for
private personal data.

- Preserve exact source and approval bytes.
- Add corrections, retractions, assertion changes, and entity lifecycle
  changes as events. Never rewrite canonical event history.
- Keep public fixtures fictional and scan for names, home paths, vault paths,
  session IDs, credentials, and private reports before publishing.
- Do not add fuzzy identity matching, silent extraction heuristics, generic SQL
  or eval commands, remote extension loading, telemetry, or hosted services.
- Treat extension Ruby entrypoints as explicitly trusted local code.
- Use named JSON commands, stable error codes, and standard input for sensitive
  values.
- Run `bin/rails test`, `bin/rubocop`, `bin/brakeman --no-pager`,
  `bin/bundler-audit`, and the fictional smoke test before release.
