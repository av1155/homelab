# AGENTS.md — Coding Agent Guide

## Project Overview

Infrastructure-as-code repository for a homelab environment. Contains Docker Compose
stacks (deployed via Portainer GitOps), Kubernetes manifests (kubeadm HA cluster with
Argo CD), and infrastructure templates. **No application source code** — this is purely
declarative config (YAML, Markdown, shell scripts).

## Repository Structure

```text
stacks/                  # Docker Compose stacks (Portainer GitOps-managed)
  <stack-name>/
    docker-compose.yaml  # Service definitions
    stack.env.example    # Env var template (actual stack.env is gitignored)
kubernetes/              # K8s manifests (kube-vip, MetalLB, Longhorn, monitoring, Argo CD)
infra-templates/         # Reusable compose templates (agent stacks, Tdarr nodes)
assets/                  # Screenshots and diagrams
.github/workflows/       # CI (ci.yaml) and auto-merge (automerge.yaml)
```

## Build / Lint / Test Commands

There is no build step or test suite. CI runs linting and security scanning.

### YAML Lint (all YAML in a stack)

```bash
yamllint stacks/<stack-name>
```

Config: `.yamllint.yaml` — extends `default`, max line length 120 (warning),
`document-start: disable`, comments require 1 space from content.

### Docker Compose Validation (single stack)

```bash
docker compose -f stacks/<stack-name>/docker-compose.yaml config --no-interpolate
```

Use `--no-interpolate` because `stack.env` files are host-injected (not in repo).

### Markdown Lint

```bash
npx markdownlint-cli2 README.md --config .markdownlint.json
```

Config: `.markdownlint.json` — extends `markdownlint/style/prettier`.

### GitHub Workflows Lint

```bash
actionlint -color -shellcheck= -pyflakes=
```

### Secrets Scanning

```bash
trufflehog filesystem --no-update --only-verified --fail stacks/
```

### Container Image Scanning

```bash
trivy image --scanners vuln --severity CRITICAL --ignore-unfixed <image>
```

### Run All Checks Locally (mimics CI)

```bash
yamllint stacks/
docker compose -f stacks/<stack>/docker-compose.yaml config --no-interpolate
actionlint
npx markdownlint-cli2 README.md --config .markdownlint.json
```

## CI Pipeline (.github/workflows/ci.yaml)

Triggers on PRs to `main`, daily schedule (14:00 UTC), and manual dispatch.

| Job                    | What it does                                         |
| ---------------------- | ---------------------------------------------------- |
| `meta_lint`            | actionlint (workflows) + markdownlint (README.md)    |
| `security_secrets`     | TruffleHog scan on `stacks/`                         |
| `detect_changes`       | Finds changed stacks (+ previously broken stacks)    |
| `validate_stacks`      | Per-stack: yamllint + `docker compose config`         |
| `security_images`      | Trivy CRITICAL scan on all images from compose files  |
| `persist_broken_cache` | Tracks sticky failures across runs                   |
| `verified_summary`     | Gate job — all above must pass for PR merge           |

PR merge method: **squash merge** (enforced by automerge workflow).

## Code Style & Conventions

### YAML Files

- **Indentation:** 4 spaces (consistent across all compose and K8s manifests)
- **Line length:** max 120 characters (warning level)
- **No `---` document-start marker** — omit the leading `---`
- **Comments:** at least 1 space between code and inline comment
- **Quoting:** quote string values that could be misinterpreted (booleans, ports)
  - `"true"`, `"false"`, `"8080:8080"`, `"0 */2 * * *"`
  - Bare values OK for clearly numeric or keyword fields (`80`, `host`, `bridge`)

### Docker Compose Conventions

- **File name:** always `docker-compose.yaml` (not `.yml`)
- **Top-level key:** `services:` only (no `version:` key — Compose V2)
- **Service ordering:** infrastructure/dependencies first, then application services
- **Required fields per service:** `image`, `container_name`, `restart`
- **`restart` policy:** `unless-stopped` (default) or `always` (critical services)
- **`container_name`:** matches the service key (e.g., `service: plex` -> `container_name: plex`)
- **Images:** use `latest` tag for rolling updates (Watchtower managed)
  - Registries: prefer `ghcr.io/`, `lscr.io/linuxserver/`, Docker Hub as fallback
- **Environment variables:**
  - Secrets use `${VAR}` interpolation from host-injected `stack.env`
  - Static config uses list syntax (`- KEY=value`) or map syntax (`KEY: value`)
  - Always include `TZ=America/New_York` for timezone-aware services
  - LinuxServer images: include `PUID=0`, `PGID=0`
- **Volumes:** absolute host paths under `/root/docker/<stack-name>-stack/`
- **Networking:** prefer `network_mode: host` where possible; use `bridge` + explicit
  `ports` when isolation is needed; use `network_mode: service:<name>` for VPN routing
- **Health checks:** use `healthcheck` for services that support it
- **Security:** add `security_opt: [no-new-privileges:true]` for sensitive services

### Secrets & Environment Files

- **Never commit secrets.** `.gitignore` blocks `**/stack.env` and `**/.env`
- Every stack with env vars must have a `stack.env.example` with placeholder values
- Secrets are injected on the host via Portainer or manual `stack.env` files

### Kubernetes Manifests

- **Indentation:** 4 spaces
- **Namespace:** always specified in metadata
- **Labels:** use `app: <name>` as standard selector
- **Storage:** use `storageClassName: longhorn` for persistent volumes
- **Ingress:** `ingressClassName: nginx`, TLS terminates at NPM (not in-cluster)

### Markdown

- Follow `markdownlint/style/prettier` rules (`.markdownlint.json`)
- Use ATX-style headings (`# H1`, `## H2`)
- Fenced code blocks with language identifiers

### Shell Scripts

- Start with `#!/usr/bin/env bash` or `#!/bin/bash`
- Use `set -euo pipefail` at the top
- Quote all variables

### Git Conventions

- **Commit messages:** Conventional Commits format
  - `<type>(<scope>): <description>` — e.g., `feat(stacks): add audiobookshelf`
  - Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
  - Scope: typically the stack name or area (e.g., `media`, `ci`, `security`, `utilities`)
  - Subject in present tense, no period, max ~50 chars
  - Body explains "why" when needed, wraps at ~72 chars
- **Branching:** trunk-based on `main`; short-lived feature branches
- **PRs:** squash-merged; auto-merge enabled for repo owner (`av1155`)
- **PR numbering:** referenced in commit messages (e.g., `(#84)`)

## Common Tasks

### Adding a New Stack

1. Create `stacks/<name>/docker-compose.yaml`
2. Create `stacks/<name>/stack.env.example` if env vars are needed
3. Follow existing compose conventions (4-space indent, `container_name`, `restart`)
4. Validate: `yamllint stacks/<name> && docker compose -f stacks/<name>/docker-compose.yaml config --no-interpolate`

### Modifying an Existing Stack

1. Edit the `docker-compose.yaml`
2. Run `yamllint` and `docker compose config --no-interpolate` to validate
3. Commit with `<type>(stacks): <description>` or `<type>(<stack-name>): <description>`

### Adding Kubernetes Resources

1. Place manifests under `kubernetes/<namespace>/`
2. Use 4-space indentation, include namespace in metadata
3. Document setup steps in `kubernetes/README.md` if applicable
