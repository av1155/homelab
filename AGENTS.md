# Agent Guidelines — Homelab Infrastructure

## Build/Lint/Test Commands

**Linting:**
- `yamllint stacks/<stack-name>` — Lint YAML files per stack (max line length: 120)
- `actionlint` — Lint GitHub Actions workflows
- `markdownlint README.md` — Lint Markdown (uses Prettier style)

**Validation:**
- `docker compose -f stacks/<stack-name>/docker-compose.yaml config --no-interpolate` — Validate single stack
- `find stacks -name "docker-compose.yaml" -exec docker compose -f {} config --no-interpolate \;` — Validate all stacks

**Security:**
- `trufflehog filesystem --no-update --only-verified --fail stacks/` — Scan for secrets
- `trivy image <image-name> --severity CRITICAL --ignore-unfixed` — Scan container images

**Single Stack Testing:** Navigate to `stacks/<stack-name>/` and run validation or test deployments locally with `docker compose up -d`

## Code Style & Conventions

**File Structure:** Each stack in `stacks/` contains `docker-compose.yaml` + `stack.env.example`

**YAML:**
- 4-space indent; max line length 120
- Use `services:` top-level key, `container_name:` for each service
- Environment variables: Use `${VAR_NAME}` references; never hardcode secrets
- Volume paths: Absolute host paths (e.g., `/root/docker/<stack>/...`)

**Naming:**
- Stacks: kebab-case (e.g., `media-vpn`, `reverse-proxy`)
- Containers: lowercase, descriptive (e.g., `adguardhome`, `plex`)
- Services: Match container names when possible

**Docker Compose Patterns:**
- `restart: unless-stopped` is standard
- Use `network_mode: host` for services requiring direct network access (DNS, Plex)
- Health checks: `test: wget --no-verbose --tries=1 --spider <url> || exit 1`
- Env vars: `TZ=America/New_York`, `PUID=0`, `PGID=0` for linuxserver.io images

**Error Handling:** All scripts use `set -euo pipefail`; CI jobs fail on first error unless explicitly continued

**Comments:** Minimal; prefer self-documenting service/variable names. Inline comments only for non-obvious config (e.g., `# PLEX_CLAIM=your_claim_token`)

**Security:** Never commit secrets; use `.env` files locally (gitignored). CI scans for verified secrets on every PR.

## Pull Request Workflow

**CI Enforcement:** All PRs must pass comprehensive CI checks before merge (workflow linting, YAML validation, secret scanning, image vulnerability scanning).

**Automerge:** PRs from `av1155` automatically squash-merge once all checks pass. **Never set PRs as draft** — draft status prevents automerge. Always open as "Ready for review".
