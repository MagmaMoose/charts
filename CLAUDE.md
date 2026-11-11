<!-- CLAUDE.md is the canonical agent-context file. AGENTS.md restates these rules. -->

Helm charts for MagmaMoose infrastructure, published as OCI artifacts to `ghcr.io/magmamoose/charts`. Two charts: `dunmir-agent` (proprietary, MikroTik monitoring/backup) and `kafka-tester` (MIT, Kafka health UI). Consumers install directly via `helm install <name> oci://ghcr.io/magmamoose/charts/<chart>`. Breaking a guard or bumping the wrong version blocks real infrastructure.

## Commands

```bash
# Lint (run for each chart)
helm lint charts/kafka-tester --values charts/kafka-tester/ci/default-values.yaml
helm lint charts/dunmir-agent

# Render and validate against Kubernetes schemas
helm template kafka-tester charts/kafka-tester --values charts/kafka-tester/ci/default-values.yaml \
  | kubeconform -strict -summary -kubernetes-version 1.33.0 -schema-location default

# Assert a guard fires (must exit non-zero without the flag)
helm template t charts/kafka-tester --set config.allowCustom=false
```

Before locating unfamiliar code, read `./PROJECT_INDEX.json` first.

[tooling]
- Prefer targeted line-range reads over whole files; use PROJECT_INDEX.json to find the location.
- grep/find/glob: return matching paths and matched lines only, never whole-file dumps.
- Commands that can flood output: pipe through head/tail/grep.
- After a successful write or edit, trust it. Don't re-read the file to verify it.

[maintenance]
- Bug that took more than an hour: document it in a comment near the code or in a PR description.
- Architectural decision: record it in a commit message or PR description.
- Public behaviour, API, config or setup changed: sync ./docs (run /claude-skills:docs-update if installed).
- PROJECT_INDEX.json stale after a new chart or a big refactor: correct the affected entries only, and update "generated" in that same edit. Never change "generated" on its own.
- Keep CLAUDE.md under ~500 tokens. Push detail into on-demand .claude/ files when they exist.
