# packer/

Packer templates for building Proxmox base VM images.

**Status:** Planned — see [Phase 1 in ROADMAP.md](../ROADMAP.md#phase-1---packer-templates-week-1-2).

## Planned structure

```text
packer/
├── ubuntu-base/
│   ├── ubuntu-base.pkr.hcl   # Proxmox builder definition
│   └── http/                  # cloud-init / preseed files
└── variables.pkrvars.hcl.example
```

## Goal

Produce a hardened, versioned Ubuntu base image on Proxmox that Terraform can
clone when provisioning new VMs or LXCs. One command builds and publishes the
template; Terraform references it by name.
