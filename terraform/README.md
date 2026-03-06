# terraform/

Terraform modules and environment configurations for Proxmox infrastructure provisioning.

**Status:** Planned — see [Phase 2 in ROADMAP.md](../ROADMAP.md#phase-2---terraform-infra-week-2-4).

## Planned structure

```text
terraform/
├── modules/
│   ├── proxmox-vm/            # Reusable VM provisioning module
│   └── proxmox-lxc/           # Reusable LXC provisioning module
├── environments/
│   └── homelab/               # Live environment (calls modules with real values)
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars.example
└── backend.tf.example         # Remote state config template
```

## Goal

Replace click-ops VM/LXC creation in Proxmox with repeatable `terraform apply`.
Modules are reusable building blocks; the `environments/homelab/` layer wires
them together with site-specific values. Secrets (API tokens, passwords) are
never committed — `.tfvars` files with real values are gitignored.
