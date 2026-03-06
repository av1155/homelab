# ansible/

Ansible roles and playbooks for post-provision host configuration.

**Status:** Planned — see [Phase 3 in ROADMAP.md](../ROADMAP.md#phase-3---ansible-configuration-week-4-6).

## Planned structure

```text
ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.yaml             # Host/group definitions
│   └── group_vars/
│       ├── all.yaml           # Variables applied to all hosts
│       ├── docker_hosts.yaml  # Docker-specific vars
│       └── k8s_nodes.yaml     # Kubernetes node vars
├── roles/
│   ├── base/                  # OS hardening, packages, SSH baseline
│   ├── docker_host/           # Docker engine, Compose plugin, system limits
│   └── monitoring_agent/      # Beszel / Dozzle agent setup
└── playbooks/
    ├── site.yaml              # Master playbook
    ├── docker-hosts.yaml
    └── k8s-nodes.yaml
```

## Goal

After Terraform provisions a VM, one Ansible run converges it to a known,
deploy-ready state. Roles are idempotent — a second run against a stable host
reports zero changes.
