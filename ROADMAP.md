# Homelab DevOps Roadmap

## Goal

Build this repo into a true end-to-end DevOps/SRE showcase: reproducible infrastructure, secure secrets flow, automated deployments, and proven reliability outcomes.

## Rules (Do Not Break)

- Keep production services stable; no big-bang migrations.
- Migrate one vertical slice at a time.
- Every phase must include rollback and written evidence.
- No secrets in Git, ever.

## Definition of Done

- Packer + Terraform + Ansible provision and configure at least one full environment path from scratch.
- Secrets are injected at runtime from a managed secrets system (Vault or equivalent), not from Portainer UI.
- At least one stack is fully automated without Portainer.
- DR drill and incident drill are documented with measured results.
- README and docs accurately reflect reality.

---

## Phase 0 — Baseline and Safety (Week 1)

**Why:** Avoid outages while learning and changing foundations.

**Deliverables:**

- [ ] `docs/runbooks/rollback-baseline.md` with rollback steps for core stacks.
- [ ] Current architecture inventory updated (services, dependencies, data paths, secrets ownership).
- [ ] Change policy written: what requires maintenance window vs normal change.

**Done when:** You can restore any one critical stack to last known good state in < 15 min.

---

## Phase 1 — Packer Templates (Week 1–2)

**Why:** Standardized base images reduce drift and speed rebuilds.

**Deliverables:**

- [ ] `packer/` with one Proxmox template build (Ubuntu/Debian base).
- [ ] Hardening baseline in template: updates, fail2ban/ssh baseline, time sync, guest tools.
- [ ] Versioned template naming convention documented.

**Done when:** You can build and publish a new template repeatably from one command.

---

## Phase 2 — Terraform Infra (Week 2–4)

**Why:** Provision infra as code, not click-ops.

**Deliverables:**

- [ ] `terraform/` with reusable modules for at least:
    - [ ] VM provisioning on Proxmox
    - [ ] network params/tags
    - [ ] cloud-init/user data wiring
- [ ] Remote state strategy documented (local initially is acceptable if backed up).
- [ ] One full vertical slice provisioned (example: 1 VM for utilities workload).

**Done when:** `terraform plan/apply/destroy` works safely for the pilot environment.

---

## Phase 3 — Ansible Configuration (Week 4–6)

**Why:** Converge hosts consistently after provisioning.

**Deliverables:**

- [ ] `ansible/` roles for:
    - [ ] `base` (users, packages, hardening basics)
    - [ ] `docker_host` (docker, compose plugin, system limits)
    - [ ] `monitoring_agent` (if needed)
- [ ] Inventory and group vars layout documented.
- [ ] Idempotency check: second run reports no changes for stable hosts.

**Done when:** Fresh VM from Terraform becomes deploy-ready via one Ansible command.

---

## Phase 4 — Secrets System (Week 6–8)

**Why:** Replace Portainer-only secret injection while keeping repo public.

**Deliverables (pragmatic order):**

- [ ] Start with Vault KV (static secrets) for pilot stack.
- [ ] Auth method chosen and documented (AppRole for homelab automation is acceptable).
- [ ] Runtime injection path implemented for one stack (env-file generation at deploy time, never committed).
- [ ] Secret rotation runbook for at least 2 high-value secrets.

**Done when:** Pilot stack deploys without secrets in repo or Portainer UI.

---

## Phase 5 — CI/CD Runner and Deployment Controls (Week 8–9)

**Why:** Enable internal deploy automation safely.

**Deliverables:**

- [ ] Self-hosted GitHub runner for trusted workflows only.
- [ ] Workflow split:
    - [ ] validate workflows (PR-safe)
    - [ ] deploy workflows (main/manual only)
- [ ] Branch protection still gates merges on CI.

**Done when:** A merged PR can trigger safe automated deploy for pilot stack.

---

## Phase 6 — Portainer Phase-Out by Pilot (Week 9–10)

**Why:** Move to fully code-driven operations without risking everything.

**Deliverables:**

- [ ] Choose one low-risk stack as migration pilot.
- [ ] Remove Portainer dependency for that stack only.
- [ ] Keep rollback path back to Portainer if needed.

**Done when:** Pilot stack lifecycle is fully managed by IaC + automation.

---

## Phase 7 — Reliability Proof (Week 10–11)

**Why:** Recruiters value evidence of operations maturity.

**Deliverables:**

- [ ] `docs/sre/slo.md` with 2-3 service SLOs and alert thresholds.
- [ ] One DR drill report with measured RTO/RPO.
- [ ] One incident drill/postmortem template + completed sample.

**Done when:** You can show measured reliability outcomes, not just architecture claims.

---

## Phase 8 — Portfolio Packaging (Week 11–12)

**Why:** Turn technical depth into clear recruiter signal.

**Deliverables:**

- [ ] 5-8 ADRs in `docs/adr/` for key tradeoffs.
- [ ] "Interview walkthrough" doc (10-minute system tour).
- [ ] README reflects actual architecture, automation, and proof artifacts.

**Done when:** A hiring manager can understand your system and engineering decisions in < 10 minutes.

---

## Minimum Weekly Cadence (Keep It Realistic)

- 2 focused build sessions (2-3h each)
- 1 docs/evidence session (1h)
- 1 retrospective update (30 min): what worked, what failed, what changed

## Anti-Patterns to Avoid

- Migrating all stacks at once
- Vault HA before proving single-node workflow
- Introducing tools without measurable outcomes
- Documentation that claims features not yet implemented

## First 3 Tasks to Start

1. Write `docs/runbooks/rollback-baseline.md` for a core stack.
2. Build first Packer template and record exact command + output in a runbook.
3. Provision first VM via `terraform plan/apply` for the pilot environment.
