# Direct dependency licenses

This inventory covers direct dependencies in version 0.1. `Gemfile.lock`
records the complete resolved dependency graph.

| Dependency | Use | License |
| --- | --- | --- |
| Rails | Application framework | MIT |
| sqlite3 | Local database adapter | BSD-3-Clause |
| Rails Event Store | Event storage and streams | MIT |
| json_schemer | Extension event-data validation | MIT |
| Propshaft | Rails asset pipeline reserved for a later local UI | MIT |
| Puma | Loopback-only Rails server reserved for a later local UI | BSD-3-Clause |
| tzinfo-data | Timezone data on Windows and JRuby | MIT |
| Bootsnap | Ruby boot cache | MIT |
| debug | Development and test debugging | Ruby and BSD-2-Clause |
| bundler-audit | Development dependency audit | GPL-3.0-or-later |
| Brakeman | Development static security analysis | Brakeman Public Use License |
| rubocop-rails-omakase | Development style checks | MIT |

Development tools are not linked into or distributed as part of the
application's runtime behavior. Recheck this inventory whenever a direct
dependency or locked version changes.
