# Homelab DevOps Roadmap

## End Goal

A fully automated, GitOps-driven homelab where **every change to this repo
reflects on the hardware** — no click-ops, no manual secret management, no
Portainer dependency. The full pipeline:

```text
Pull Request
  → GitHub Actions (validate: lint, compose check, security scan)
  → Merge to main
  → GitHub Actions (deploy: self-hosted runner inside the homelab)
      → Ansible: SSH to target LXC/VM
          → decrypt secrets (sops + age)
          → write stack.env
          → docker compose pull && docker compose up -d
      → kubectl apply (for Kubernetes workloads via Argo CD)
```

All tools used are **free and open-source**. The repo stays public. Secrets
never appear in plaintext in Git.

---

## Secrets Strategy: sops + age

**Why `sops` + `age` instead of HashiCorp Vault:**

HashiCorp Vault is powerful but requires a permanently running service that
must be unsealed on every restart — if it's down, your entire deploy pipeline
is broken. For a homelab, that operational overhead is a liability.

`sops` + `age` achieves the same guarantee with zero extra services:

- Secret files (e.g. `stacks/vaultwarden/secrets.enc.env`) are encrypted
  with your `age` key and committed to the repo
- The `age` private key lives only on the self-hosted runner and your machine
- GitHub Actions decrypts at deploy time using a repository secret (`AGE_KEY`)
- Ansible uses the same mechanism when running playbooks
- Works identically for Docker stack env files and Kubernetes Secrets

This is auditable, reproducible, free, and has no single point of failure.

---

## Rules (Do Not Break)

- Keep production services stable — migrate one stack at a time.
- Every phase must have a working rollback path before you proceed.
- No plaintext secrets in Git, ever. Only `*.enc.env` files.
- The runner only deploys from `main`. PRs only validate.

---

## Definition of Done

- Packer builds a hardened base image from one command.
- Terraform provisions any LXC/VM from code — no Proxmox UI click-ops.
- Ansible converges any host to deploy-ready state after provisioning.
- A merged PR to `main` automatically deploys the changed stack(s) to the
  correct LXC via the self-hosted runner — no manual steps.
- Secrets are encrypted in the repo, decrypted only at deploy time.
- The Kubernetes cluster is rebuilt and managed through the same pipeline.
- Portainer is disabled (kept as emergency break-glass only).
- SLOs and a DR drill report exist with real measured numbers.
- A hiring manager can understand the full system in under 10 minutes.

---

## Phase 0 — Baseline and Safety

**Why:** You need a safe fallback before changing anything foundational.
If something breaks mid-migration, you need to restore in under 15 minutes.

**Deliverables:**

- [ ] `docs/runbooks/rollback-baseline.md` — step-by-step restore for each
  critical stack (vaultwarden, dns, reverse-proxy, media, utilities).
  Include: what to check, which compose file to use, where data lives.
- [ ] Secrets inventory — list every stack that uses `${VAR}` interpolation,
  what each variable is, and where it currently lives (Portainer UI).
  This is your migration checklist for Phase 4.
- [ ] Verify Proxmox snapshots exist for all LXC containers before proceeding.

**Done when:** You can restore any one critical stack to last known good state
in under 15 minutes, documented and tested.

---

## Phase 1 — Packer: Hardened Base Images

**Why:** Every VM and LXC you provision should start from a known, hardened,
consistent baseline. Packer automates building that image on Proxmox so you
never manually install an OS again.

**What you'll build:** `packer/ubuntu-base/` — a Proxmox VM template built
from the Ubuntu 24.04 cloud image with:

- Unattended upgrades, fail2ban, SSH hardening (key-only, no password)
- QEMU guest agent, cloud-init support
- Timezone set, NTP configured
- Versioned template name (e.g. `ubuntu-24.04-base-v1`)

**Deliverables:**

- [ ] `packer/ubuntu-base/ubuntu-base.pkr.hcl` — Proxmox builder definition
- [ ] `packer/ubuntu-base/http/user-data` — cloud-init seed config
- [ ] `packer/variables.pkrvars.hcl.example` — all required variables documented
  (Proxmox API URL, token, node name, storage pool)
- [ ] Build tested: `packer build -var-file=variables.pkrvars.hcl ubuntu-base/`
  produces a usable template in Proxmox
- [ ] `docs/proxmox/packer-templates.md` — template naming convention and
  rebuild procedure

**Done when:** `packer build` runs from one command and creates a named
template visible in Proxmox. Destroying and rebuilding it works cleanly.

---

## Phase 2 — Terraform: Proxmox Provisioning

**Why:** New VMs and LXCs should come from `terraform apply`, not from
clicking through the Proxmox UI. This makes the cluster fully reproducible
and documents exactly what exists.

**Terraform provider:** `bpg/proxmox` (most feature-complete, actively
maintained, supports both VMs and LXCs).

**What you'll build:**

```text
terraform/
├── modules/
│   ├── proxmox-vm/      # Clone from Packer template, cloud-init, sizing
│   └── proxmox-lxc/     # LXC container from base image, networking, mounts
├── environments/
│   └── homelab/
│       ├── main.tf          # Calls modules for all current LXCs and VMs
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── backend.tf.example       # Remote state config (local file initially)
```

**Current inventory to codify** (12 LXCs + 7 VMs):

LXCs: `ct-dns`, `ct-proxy`, `ct-portainer`, `ct-database`, `ct-utilities`,
`ct-media`, `ct-kestra`, `ct-tdarr-node-01`, `ct-tdarr-node-02`,
`ct-dokploy`, `ct-upsnap`, `ct-security`

VMs: `k8s-master-01/02/03`, `k8s-worker-01/02/03`, `home-assistant`

**Deliverables:**

- [ ] `proxmox-vm` module: clone Packer template, set CPU/RAM/disk,
  cloud-init network config, SSH key injection
- [ ] `proxmox-lxc` module: create LXC from base image, set resources,
  bind mounts (NFS, `/dev/dri` for GPU passthrough), networking
- [ ] `environments/homelab/main.tf` calls both modules for at least the
  pilot LXC (`ct-utilities`) and the 6 K8s VMs
- [ ] `terraform.tfvars.example` documents every required variable
  (API token, node names, storage pools, IP ranges)
- [ ] Remote state: local `terraform.tfstate` stored on NAS backup path,
  documented in `backend.tf.example`
- [ ] `terraform plan` shows zero diff against the existing pilot environment
- [ ] `terraform destroy` and `terraform apply` cleanly recreate the pilot

**Done when:** The pilot LXC (`ct-utilities`) and all 6 K8s VMs can be
destroyed and recreated from `terraform apply` with no manual Proxmox steps.

---

## Phase 3 — Ansible: Host Configuration

**Why:** After Terraform provisions a host, Ansible converges it to a
deploy-ready state — installs Docker, applies hardening, configures NFS
mounts, deploys the agents stack, and prepares it for compose deployments.

**What you'll build:**

```text
ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.yaml          # All LXCs and VMs with IPs and groups
│   └── group_vars/
│       ├── all.yaml        # SSH user, timezone, common packages
│       ├── docker_hosts.yaml   # Docker version, compose plugin, log driver
│       └── k8s_nodes.yaml  # kubelet, kubeadm, containerd settings
├── roles/
│   ├── base/               # apt update, unattended-upgrades, fail2ban,
│   │                       # SSH hardening, NTP, sysctl tuning
│   ├── docker_host/        # Docker engine, Compose plugin, daemon.json,
│   │                       # NFS mounts, /dev/dri passthrough where needed
│   ├── agents/             # Deploy host-templates/agents/ stack
│   │                       # (beszel, portainer-agent, dozzle, dockerproxy,
│   │                       #  watchtower) with correct hostnames
│   └── k8s_node/           # containerd, kubelet, kubeadm pre-reqs,
│                           # kernel modules, sysctl for K8s
├── playbooks/
│   ├── site.yaml           # Run all roles against all hosts (idempotent)
│   ├── docker-hosts.yaml   # base + docker_host + agents
│   ├── k8s-nodes.yaml      # base + k8s_node
│   └── deploy-stack.yaml   # Called by CI runner to deploy one stack
└── sops.yaml               # sops config: which files to encrypt, age recipient
```

**Deliverables:**

- [ ] All 4 roles written and tested against the pilot LXC (`ct-utilities`)
- [ ] `deploy-stack.yaml` playbook: takes `stack=<name>` variable, SSHes to
  target host, decrypts `stacks/<name>/secrets.enc.env` with `sops`,
  writes `stack.env`, runs `docker compose pull && docker compose up -d`
- [ ] `ansible-playbook playbooks/site.yaml` is fully idempotent — second
  run on a stable host reports zero changes
- [ ] `hosts.yaml` documents all 12 LXCs and 7 VMs with correct IPs
  (`10.0.10.x`) and group membership

**Done when:** Destroying the pilot LXC (`ct-utilities`), recreating it with
Terraform, and running `ansible-playbook playbooks/docker-hosts.yaml` brings
it to fully operational state with all agents running — zero manual steps.

---

## Phase 4 — Secrets: sops + age Encryption

**Why:** Every stack that currently uses Portainer-injected env vars needs
those secrets stored somewhere safe. sops + age encrypts them in the repo
(readable only with your private key) so deploys are fully automated without
exposing anything publicly.

**How it works:**

```text
1. You run: sops --encrypt stacks/vaultwarden/secrets.env \
              > stacks/vaultwarden/secrets.enc.env
2. Commit secrets.enc.env  (safe — encrypted with your age public key)
3. CI runner has AGE_KEY secret → sops --decrypt at deploy time
4. Ansible writes the decrypted content to stack.env on the host
5. docker compose reads stack.env as normal
```

**Kubernetes:** Use the same pattern with `sops` +
`kubernetes-sigs/external-secrets` or simply `kubectl create secret`
called from Ansible with decrypted values — no extra operator required.

**Deliverables:**

- [ ] Install `age` and `sops`; generate homelab `age` keypair; store
  private key in GitHub Actions secret `AGE_KEY` and in `~/.config/sops/age/`
- [ ] `.sops.yaml` at repo root — maps `stacks/**/secrets.enc.env` to
  your age public key
- [ ] `*.enc.env` files created for all stacks that have secrets (see
  Phase 0 inventory): dns, homepage, kestra, mariadb, media, media-monitoring,
  media-vpn, upsnap, utilities, vaultwarden, wireguard
- [ ] `stack.env` and `secrets.env` added to `.gitignore` (plaintext never
  committed)
- [ ] `deploy-stack.yaml` Ansible playbook updated to decrypt with sops
  before writing `stack.env`
- [ ] Secret rotation tested: update encrypted value, commit, CI deploys,
  service picks up new value without manual intervention

**Done when:** Every stack's secrets live only as encrypted files in the
repo. The CI runner can deploy any stack end-to-end without a human touching
a secret in plaintext.

---

## Phase 5 — CI/CD: Self-Hosted Runner and Deploy Workflows

**Why:** The self-hosted runner is what makes changes to this repo
automatically reflect on the hardware. It runs inside your homelab (on a
dedicated LXC), has network access to all other LXCs, holds the `age`
private key, and executes Ansible playbooks on merge.

**Architecture:**

```text
GitHub Actions (validate — runs on GitHub-hosted runners, safe for PRs):
  - yamllint, markdownlint, actionlint
  - docker compose config --no-interpolate
  - trufflehog secrets scan
  - trivy image scan (changed stacks only on PRs)

GitHub Actions (deploy — runs on self-hosted runner, main branch only):
  - Detect which stacks changed
  - For each changed stack:
      ansible-playbook playbooks/deploy-stack.yaml -e stack=<name>
  - On infra changes (terraform/ or packer/ modified):
      terraform plan (show only, not auto-apply — require manual approve)
```

**Why not auto-apply Terraform from CI:** Terraform destroy/apply on
production infra from an automated runner is high risk. The pattern used
by most SRE teams: CI runs `terraform plan` and posts the diff as a PR
comment; you manually run `terraform apply` after review. This is correct
and is the answer you give in an interview.

**Deliverables:**

- [ ] Self-hosted GitHub runner deployed on a new LXC (`ct-runner`) or
  on `ct-portainer` — provisioned by Terraform, configured by Ansible
- [ ] `.github/workflows/deploy.yaml` — triggers on push to `main`,
  detects changed stacks via `git diff`, calls Ansible deploy playbook
  for each changed stack
- [ ] `.github/workflows/terraform-plan.yaml` — triggers on PRs touching
  `terraform/`, runs `terraform plan`, posts output as PR comment
- [ ] Workflow separation enforced: deploy workflow has
  `if: github.ref == 'refs/heads/main'`; validate workflow runs on all PRs
- [ ] `docs/runbooks/runner-setup.md` — how to rebuild the runner LXC
  if it's lost (it's not special, just re-provision with Terraform + Ansible)

**Done when:** Editing a `docker-compose.yaml` file, opening a PR (CI
validates), merging to `main` (runner SSHes to target LXC and deploys the
stack) — all without touching the homelab manually.

---

## Phase 6 — Kubernetes: Rebuild via the Pipeline

**Why:** The K8s cluster needs to be rebuilt (broken since the IP migration).
Do it right this time — provision the 6 VMs via Terraform, configure them
via Ansible, initialize the cluster, and have Argo CD pull manifests from
this repo. This proves the full Packer → Terraform → Ansible → GitOps
pipeline works on your most complex workload.

**What the pipeline does:**

```text
packer build → ubuntu-base template in Proxmox
terraform apply → 3× k8s-master VMs + 3× k8s-worker VMs (clone template)
ansible-playbook k8s-nodes.yaml → containerd, kubelet, kubeadm pre-reqs
manual: kubeadm init on master-01, kubeadm join on all other nodes
ansible-playbook k8s-post-init.yaml → kube-vip, Flannel CNI, MetalLB,
                                       NGINX Ingress, Longhorn, Argo CD
Argo CD → watches kubernetes/ in this repo → applies all manifests
```

`kubeadm init/join` stays manual (or scripted but not auto-applied from CI)
because it's a one-time cluster bootstrap, not a recurring deploy operation.

**Deliverables:**

- [ ] `terraform/environments/homelab/main.tf` includes all 6 K8s VMs
  with correct sizing (from `homelab_inventory.md`)
- [ ] `ansible/roles/k8s_node/` fully tested — fresh VM becomes
  kubeadm-ready after one playbook run
- [ ] `ansible/playbooks/k8s-post-init.yaml` — post-bootstrap setup:
  kube-vip static pod, Flannel CNI, MetalLB, NGINX Ingress, Longhorn install
- [ ] Argo CD deployed and pointed at `kubernetes/` in this repo —
  all manifests in `kubernetes/` are managed by Argo CD, not `kubectl apply`
- [ ] `docs/proxmox/k8s-rebuild.md` — exact commands to rebuild the cluster
  from scratch using this pipeline (the receipts interviewers ask for)
- [ ] K8s secrets handled with sops: `kubectl create secret` called from
  Ansible with sops-decrypted values; no plaintext secret in `kubernetes/`

**Done when:** The K8s cluster is running, Argo CD is managing the manifests
in `kubernetes/`, and you can document the exact steps to rebuild it from
scratch in under 2 hours using only this repo.

---

## Phase 7 — Full Stack Migration (Portainer Off)

**Why:** This is where everything comes together. Migrate all remaining
stacks from Portainer GitOps to Ansible + CI runner deploys, then disable
Portainer as the deploy mechanism.

**Migration order (lowest risk to highest):**

1. `utilities` — monitoring tools, easy to restore if broken
2. `dns` — critical but simple; test in off-hours
3. `reverse-proxy` — critical path; have rollback ready
4. `media` + `media-vpn` + `media-monitoring` — large but non-critical
5. `vaultwarden` — sensitive; do last; verify backup before migrating
6. Remaining: `kestra`, `mariadb`, `homepage`, `wireguard`, `openwebui`,
   `portainer`, `upsnap`

**Deliverables:**

- [ ] All 14 stacks have `secrets.enc.env` files (from Phase 4)
- [ ] `deploy-stack.yaml` tested and working for all 14 stacks
- [ ] All stacks removed from Portainer GitOps; Portainer set to
  "no auto-deploy" — kept running as break-glass UI only
- [ ] CI deploy workflow covers all stacks via changed-file detection
- [ ] `docs/runbooks/rollback-baseline.md` updated with new deploy
  mechanism rollback steps

**Done when:** Every stack in this repo deploys via CI runner + Ansible.
Portainer UI is running but not the deploy mechanism.

---

## Phase 8 — Reliability Evidence

**Why:** Architecture claims without measurements mean nothing in an
interview. This phase produces the artifacts that back up your claims.

**Deliverables:**

- [ ] `docs/sre/slo.md` — define 2-3 SLOs with real numbers from Uptime
  Kuma (e.g. "reverse-proxy availability > 99.9% over 30 days").
  Include error budget and alert thresholds.
- [ ] DR drill: shut down one Proxmox node, measure actual RTO for HA
  failover, document it in `docs/sre/dr-drill-01.md`
- [ ] Postmortem template in `docs/sre/postmortem-template.md` + one
  completed example from a real past incident (K8s IP migration is perfect)
- [ ] `docs/adr/` — 5-8 Architecture Decision Records for key choices:
  - Why sops + age over HashiCorp Vault
  - Why Ansible for deploy over Portainer GitOps
  - Why Terraform bpg/proxmox over Telmate provider
  - Why Flannel over Calico for home K8s
  - Why self-hosted runner over GitHub-hosted for deploys
  - Why Longhorn over NFS-only for K8s storage

**Done when:** Every architecture claim in the README links to a runbook,
drill report, or ADR that proves it.

---

## Phase 9 — Portfolio Packaging

**Why:** A hiring manager spends 5-10 minutes on a repo. Make every second
count.

**Deliverables:**

- [ ] README updated to reflect the completed pipeline — replace "planned"
  notes with real descriptions and links to evidence
- [ ] `docs/interview-walkthrough.md` — a 10-minute guided tour of the repo:
  what problem each tool solves, one interesting decision per phase, what
  you'd do differently
- [ ] Architecture diagram updated if the pipeline changes the topology
- [ ] All `docs/proxmox/` notes cleaned up — remove any stale IPs or
  placeholder text

**Done when:** You can hand a recruiter the repo URL and walk them through
the full system in 10 minutes, showing working CI runs, encrypted secrets,
Argo CD syncing manifests, and measured reliability numbers.

---

## Parallel Work (Do Throughout, Not as Separate Phases)

These don't block any phase — work on them during documentation sessions:

- Write ADRs as you make each tool decision (don't wait until Phase 8)
- Update `docs/sre/slo.md` as soon as Uptime Kuma has 30 days of data
- Update the README after each phase to reflect reality
- Keep `docs/proxmox/` notes current as you change IPs and hostnames

---

## Realistic Time Estimates

These tools are new to you. Expect the learning curve, not the ideal case.

| Phase | Optimistic | Realistic |
| --- | --- | --- |
| 0 — Baseline safety | 1 weekend | 1 weekend |
| 1 — Packer | 1 weekend | 2 weekends |
| 2 — Terraform | 2 weekends | 3–4 weekends |
| 3 — Ansible | 2 weekends | 3 weekends |
| 4 — sops + age | 1 weekend | 1–2 weekends |
| 5 — CI/CD runner | 1 weekend | 2 weekends |
| 6 — K8s rebuild | 2 weekends | 3–4 weekends |
| 7 — Full migration | 2 weekends | 3 weekends |
| 8 — Reliability evidence | 1 weekend | 2 weekends |
| 9 — Portfolio packaging | 1 weekend | 1 weekend |
| **Total** | **~13 weekends** | **~22 weekends** |

At 2-3 focused sessions per week (~4-6h/week), realistic completion is
**4-6 months**. That is not slow — this is a production-grade IaC pipeline
built by one person learning the tools. It will be impressive.

---

## Anti-Patterns to Avoid

- Migrating all stacks at once — do one, verify, then the next
- Auto-applying Terraform from CI — always `plan` from CI, `apply` manually
- Starting K8s before the Ansible + sops pipeline is working on Docker stacks
- HashiCorp Vault before you have a working deploy pipeline (adds failure mode)
- Writing ADRs and SLOs before you have real data to put in them
- Claiming features in the README that aren't implemented yet

---

## Toolchain Summary

| Tool | Role | Free |
| --- | --- | --- |
| Packer (HashiCorp) | Build Proxmox VM templates | Yes |
| Terraform + bpg/proxmox | Provision VMs and LXCs | Yes |
| Ansible | Configure hosts, deploy stacks | Yes |
| sops + age | Encrypt secrets in repo | Yes |
| GitHub Actions | Validate on PRs | Yes |
| Self-hosted GitHub runner | Deploy on merge to main | Yes |
| Argo CD | GitOps for Kubernetes manifests | Yes |
| Portainer | Break-glass UI only (disabled for deploys) | Yes |
