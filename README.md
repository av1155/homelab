# Homelab

This repository contains the configuration of my self-hosted **homelab**, built on **Proxmox** (VM/LXC orchestration) and managed as code in Git. It defines infrastructure services, applications, and automation workflows that are deployed reproducibly using Docker Compose.

> 💡 This homelab demonstrates my ability to design, automate, and operate **production-grade infrastructure**

## Skills Snapshot

- Infrastructure: Proxmox (HA clustering), Kubernetes, Docker, ZFS, NAS
- Automation: GitOps, GitHub Actions, Portainer Stacks, Dokploy, Kestra
- CI/CD & Observability: TruffleHog, Uptime Kuma, Dozzle
- Networking & Security: Cloudflare Zero Trust, WireGuard, VLANs, firewalls
- Backup & DR: ZFS snapshots, Synology NAS, multi-tier cloud backups

![Homepage Dashboard](images/Homelab.jpeg)

![Proxmox Cluster Overview](images/Proxmox.jpeg)

## Workflow

- **Infrastructure**: Proxmox provides VM/LXC orchestration, networking, and storage.
- **Applications**: Deployed with Docker Compose (using Portainer Git Stacks for automation).
- **Configuration**: Version-controlled in Git for reproducibility.
- **Secrets**: Handled via Portainer secrets or host environment, never committed.

## CI

A lightweight GitHub Actions workflow runs on each push/PR:

- **Lints YAML**: Checks all `.yaml` files for formatting/style issues.
- **Validates Compose**: Ensures every `docker-compose.yaml` parses correctly.
- **Scans for secrets**: Detects verified secrets with TruffleHog.

Keeping the homelab **consistent, reproducible, and safe**.

---

# Infrastructure Overview

I designed and operate a **highly available, production-grade homelab** that simulates modern cloud-native environments. It is engineered for **resilience, observability, automated deployments, and scalable application hosting**, closely mirroring real-world production infrastructure.

---

## Compute & Clustering

- **Proxmox 2-node HA cluster**:

    - Intel NUC 12 i5-1240P (SSD + NVMe/ZFS)
    - Intel NUC 11 i5-1145G7 (SSD + NVMe/ZFS)
    - **Raspberry Pi 5 (8GB RAM + NVMe)** as QDevice for quorum & secondary services.

- **Workload strategy**:

    - **LXCs** → lightweight Dockerized services for low overhead & easy management.
    - **VMs** → Kubernetes master + 3 workers for orchestration, education, and production-grade experimentation.

- **HA groups & replication**:

    - Configured with node priorities and automatic failover (<3 min downtime).
    - Replication tuned for resilience, limiting data loss to <15 minutes.

---

## Storage & Backup

- **ZFS-backed NVMe storage** on each node → enabling snapshots, HA replication, and high-performance workloads.
- **Synology DS423+ NAS** (6GB RAM, 2×12TB HDD in SHR, dual NVMe SSD cache/fast volume):

    - NFS mounts for media and raw storage.
    - **Backup strategy**:

        - Proxmox snapshots → NAS → Cloud (Google Drive/OneDrive) + local SSD.
        - One-click recovery for VMs and LXCs.

    - NVMe read cache improves performance for active workloads.

---

## Networking & Security

- **Ubiquiti UniFi Express 7 router** + **2.5GbE managed switch** (VLANs for isolation & security).
- **Cloudflare Domain & Zero Trust Access**:

    - All external services routed through **Cloudflare’s orange-cloud proxy**, exposing only HTTPS (443) while masking the home IP from the public internet.
    - **Automated TLS certificates** issued and renewed via the Cloudflare API, ensuring secure, hands-off certificate management.
    - **Zero Trust policies** (identity-based access, MFA, and per-service restrictions) applied at the Cloudflare edge for least-privilege, production-grade security.

- **Nginx Proxy Manager** for internal TLS & routing.
- **WireGuard VPN** for fast, encrypted external access.
- **AdGuard Home (dual instances)** for DNS filtering & redundancy.
- **Firewall rules** configured per-service for least-privilege access.

---

## Deployment & Automation

- **GitOps-inspired CI/CD**:

    - Portainer stacks synced with public GitHub repository.
    - Automated linting, docker-compose validation, and TruffleHog scans.
    - Secrets injected at host level for reproducibility.

- **Dokploy**:

    - Webhook-driven deployments from GitHub commits/PRs.
    - Automates dockerization, provisioning, and scaling.
    - Full DB + config backups to Cloudflare R2 Object Storage.

- **Supporting toolchain**:

    - **Kestra** for orchestration & automation.
    - **Dozzle** for real-time container logs.
    - **Uptime Kuma** for monitoring & notifications.

---

## Design Principles

- **Cloud-Centric & Resilient**: Mirrors enterprise-grade HA and DR strategies.
- **Efficient Workload Separation**: Media, databases, orchestration, proxy, and security services split across nodes.
- **Scalable & Secure**: VLAN isolation, VPN-only access, and Cloudflare Zero Trust proxy.
- **Learning-Oriented, Production-Ready**: Kubernetes VMs for education and LXCs for reliable, resource-efficient operations.
- **Cost-Effective Cloud Simulation**: Runs locally but architected like a scalable mini cloud provider.

---

## Outcome

This homelab demonstrates the ability to **design, operate, and maintain complex, highly available infrastructure**. It highlights practical experience with:

- High Availability & Clustering (Proxmox, ZFS, HA groups)
- Containerization & Orchestration (Docker, Kubernetes)
- CI/CD & GitOps workflows (Portainer, Dokploy, GitHub Actions)
- Observability & Monitoring (Uptime Kuma, Dozzle)
- Security & Networking (Cloudflare Zero Trust, WireGuard, VLANs, firewalls)
- Backup & Disaster Recovery (ZFS snapshots, NAS, multi-tier cloud backups)

This setup reflects a **production-grade DevOps/SRE skill set** built from the ground up.

---

## Service & Stack Reference (Detailed)

<details>
<summary>Click to expand</summary>

```
stacks/
  ├── dns/                     # DNS + config sync
  │   ├── docker-compose.yaml  # adguardhome, adguardhome-sync
  │   └── stack.env.example
  │
  ├── homepage/                # Homelab dashboard
  │   ├── docker-compose.yaml  # homepage
  │   └── stack.env.example
  │
  ├── kestra/                  # Workflow orchestration
  │   ├── docker-compose.yaml  # postgres, kestra
  │   └── stack.env.example
  │
  ├── mariadb/                 # Relational DB + admin
  │   ├── docker-compose.yaml  # mariadb, phpmyadmin
  │   └── stack.env.example
  │
  ├── media/                   # Media apps
  │   ├── docker-compose.yaml  # prowlarr, radarr, sonarr, plex, overseerr, maintainerr, tdarr, recyclarr, flaresolverr, metube
  │   └── stack.env.example
  │
  ├── media-vpn/               # VPN-protected downloads
  │   ├── docker-compose.yaml  # gluetun, qbittorrent, deunhealth
  │   └── stack.env.example
  │
  ├── openweb-ui/              # Local LLM UI + meta search
  │   ├── docker-compose.yaml  # open-webui, searxng
  │   └── stack.env.example
  │
  ├── reverse-proxy/           # Public reverse proxy
  │   └── docker-compose.yaml  # nginx-proxy-manager
  │
  ├── utilities/               # Tools & monitoring
  │   ├── docker-compose.yaml  # uptimekuma, dozzle, it-tools, libretranslate, openspeedtest, peanut
  │   └── stack.env.example
  │
  ├── vaultwarden/             # Password manager + backups
  │   ├── docker-compose.yaml  # vaultwarden, vaultwarden-backup
  │   └── stack.env.example
  │
  └── wireguard/               # VPN server
      ├── docker-compose.yaml  # wg-easy
      └── stack.env.example
```

- Each directory = one **stack** (a set of related services).

---

- **dns/** – _AdGuard Home + adguardhome-sync_: network-wide DNS filtering, policy replication, and API-driven config.
- **reverse-proxy/** – _Nginx Proxy Manager_: HTTP(S) ingress, TLS via Cloudflare API, stream (SMTP/IMAP/POP3) proxying.
- **wireguard/** – _WG‑Easy_: secure remote access, opinionated defaults, audited iptables rules.
- **utilities/** – _Uptime Kuma, Dozzle, IT‑Tools, LibreTranslate, OpenSpeedTest, Peanut_:

    - **Uptime Kuma**: black‑box monitoring & alerting.
    - **Dozzle**: live container logs; remote agents for multi‑node visibility.
    - **Peanut**: tunnel / remote access UI with auth.
    - **LibreTranslate** + **OpenSpeedTest** + **IT‑Tools**: internal tooling surface.

- **homepage/** – _getHomepage_: single-pane-of-glass dashboard sourced from environment variables and APIs.
- **media/** – _Prowlarr, Radarr, Sonarr, Plex, Overseerr, Maintainerr, Tdarr, Recyclarr, FlareSolverr, MeTube_:

    - Shows **event‑driven automation**, **GPU/VA‑API transcoding**, shared NFS volumes, and service-to-service auth keys.

- **media-vpn/** – _Gluetun + qBittorrent + Deunhealth_: policy‑routed egress behind WireGuard, health‑gated app start.
- **mariadb/** – _MariaDB + phpMyAdmin_: stateful services separated from app stacks; custom ini/config mounts.
- **vaultwarden/** – _Vaultwarden + backup_: secrets vault + scheduled encrypted backups (retention, timestamping).
- **kestra/** – _Kestra + Postgres_: workflow orchestration with externalized DB, healthchecks, and ephemeral workdirs.
- **openweb-ui/** – _Open‑WebUI + SearxNG_: local LLM UI and meta search; host socket isolation and bind‑mounted data.

**Secrets & Config Strategy**

- Code & Compose in Git; **`stack.env.example`** committed for reproducibility.
- Real secrets injected at the **Portainer host/stack level** (and/or Vaultwarden), not stored in Git.
- CI enforces YAML style, Compose validity, and **verified** secret scanning.

</details>

---
