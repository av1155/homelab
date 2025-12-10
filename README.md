# Homelab – Cloud-Inspired Infrastructure

[![CI — Validate Stacks, Security & Lint](https://github.com/av1155/homelab/actions/workflows/ci.yaml/badge.svg)](https://github.com/av1155/homelab/actions/workflows/ci.yaml)

> **TL;DR:**
> This homelab is a **production-like environment** designed for **high availability, automation, observability, and resilience**.
> It demonstrates hands-on experience with **Proxmox clustering, Kubernetes, Docker, GitOps, CI/CD, Cloudflare Zero Trust, backups, and monitoring**.
> All services are defined as code in this repo.

This project is my **personal lab** and represents the real-world DevOps/SRE skills I bring:

- Automating deployments with **GitOps & CI/CD**
- Designing for **high availability and disaster recovery**
- Operating **secure, cloud-centric infrastructure**
- Building **observable, scalable, reproducible systems**

---

## Key Docs

- [**Kubernetes Production Setup**](./kubernetes/README.md)  
  Step-by-step HA cluster config: kube-vip, MetalLB, Longhorn, backups, Prometheus/Grafana, Argo CD.
- [**Homelab Inventory & Cloud Cost Comparison**](./homelab_inventory.md)  
  Hardware, one-time spend, AWS-equivalent monthly cost, and 3-year savings.

---

## Skills Snapshot

- **Infrastructure & Clustering** – Proxmox HA, Kubernetes, Docker, ZFS, Synology NAS, Longhorn
- **Automation & IaC** – GitOps, Argo CD, GitHub Actions, Portainer GitOps, Dokploy, (planned: Terraform modules and Ansible Playbooks for Proxmox/AWS)
- **Observability & Ops** – Prometheus + Grafana, Beszel, Uptime Kuma, Dozzle, Kestra
- **Networking & Security** – Cloudflare Proxy + Zero Trust, NPM (LXC) with in-cluster NGINX Ingress + MetalLB, AdGuard Home (dual DNS), VLAN segmentation, WireGuard VPN, firewall rules
- **Backup & DR** – ZFS replication, Synology NAS (Hyper Backup + cloud sync), Cloudflare R2 off-site storage

---

## Stats at a Glance

- **GitOps:** 11 stacks · 28 containers
- **Portainer-managed fleet (all environments):** 29 stacks · 95 containers across 11 Docker environments
- **Resilience:** **RTO ≤ 3m** (Proxmox HA), **RPO ≈ 15m** (ZFS replication)
- **Monitoring:** Prometheus + Grafana dashboards · 64 checks in Uptime Kuma · 10 hosts in Dozzle · 10 systems in Beszel
- **Availability snapshot:** Core infra **100%** · Exposed Services **99.79%** · Personal Websites **99.93%**

---

## Compute & Clustering

- **Proxmox 3-node HA cluster** (HA failover; ZFS snapshots/replication) → 40 vCPUs, 96 GB RAM
- **Workload separation**:
    - **LXCs** → lightweight Dockerized services (Portainer managed)
    - **VMs** → Kubernetes cluster (**3 control planes + 3 workers**)

_Proxmox Dashboard:_
![Proxmox Cluster Overview](assets/Proxmox.jpeg)

---

## Kubernetes Cluster

- **Cluster type:** kubeadm, 3 control planes + 3 workers (running on Proxmox VMs)
- **Networking:** Flannel CNI, MetalLB for LoadBalancer IPs, NGINX Ingress
- **Storage:** Longhorn HA volumes, backed up to Synology NAS (NFS)
- **Observability:** Prometheus + Grafana, with persistent dashboards
- **GitOps:** Argo CD for application lifecycle
- **Edge:** TLS terminates at Nginx Proxy Manager, fronted by Cloudflare proxy/DNS

👉 [Full K8s config](./kubernetes/README.md)

---

## Deployment & Automation

- **GitOps with Portainer**
    - Stacks reconciled directly from GitHub
    - GitHub Actions: linting, Compose validation, secret scanning (TruffleHog), image scanning (Trivy)
    - Host-level secret injection (no secrets in Git)
    - Portainer runs in a dedicated HA LXC, with **Portainer Agents + baseline agents** deployed across all nodes/devices:
        - `portainer-agent` – centralized Docker management
        - `beszel-agent` – metrics & alerting
        - `dozzle-agent` – log aggregation
        - `docker-socket-proxy` – secure Docker API access
        - `watchtower` – automated updates & Slack reporting  
          **Deployed on 11 Docker environments → 29 stacks / 95 containers total**

- **CI/CD with Dokploy**
    - Webhook-triggered deployments for custom apps (Flask, Next.js, static sites, etc.)
    - Docker Swarm cluster deployments with horizontal scaling
    - Automated DB backups stored in **Cloudflare R2 (S3-compatible)** for durability & DR

---

## Monitoring & Observability

The homelab uses a **multi-layer monitoring stack** for real-time metrics, logs, uptime, and dashboards — combining **Prometheus + Grafana, Beszel, Dozzle, and Uptime Kuma**.  
This provides **end-to-end visibility**, proactive SMTP alerts, and lightweight dashboards.

### Prometheus + Grafana

- Collects cluster-wide metrics (Kubernetes, containers, nodes)
- Grafana dashboards for long-term visibility and troubleshooting
- Persistent storage ensures historical metrics are retained across restarts

_Grafana Dashboard:_  
![Grafana Dashboard](assets/Grafana.jpeg)

### Beszel

- **Agents deployed** on all LXCs, the NAS (DS423+), and the Raspberry Pi
- Tracks CPU, memory, disk, network, GPU, load averages, and temperatures
- Alert thresholds: downtime (10m), CPU >80%, memory >80%, disk >80%, temp >85°C

_Beszel Dashboard:_  
![Beszel Dashboard](assets/Beszel.jpeg)

### Dozzle

- Centralized Docker log visibility via lightweight agents
- Enables quick debugging and operational awareness

_Dozzle Logs View:_  
![Dozzle Logs](assets/Dozzle.jpeg)

### Uptime Kuma

- External + internal uptime checks for services and infrastructure
- 64 checks configured, complementing Beszel + Dozzle

_Uptime Kuma Dashboard:_  
![Uptime Kuma](assets/Uptime-Kuma.jpeg)

---

## CI/CD

This repository uses a **CI/CD pipeline** to ensure every stack stays **valid, secure, and ready for Portainer GitOps deployment**.

### What’s enforced

- **Workflow & docs linting** – consistent workflows and clean documentation
- **YAML & Compose checks** – validate syntax and Docker Compose configs per stack
- **Secrets scanning** – block commits containing verified secrets
- **Image scanning** – weekly Trivy runs detect CRITICAL CVEs
- **Code scanning** – CodeQL ensures no critical security alerts

### Why it matters

- Portainer GitOps only deploys **healthy stacks**, reducing drift and risk
- Security and quality gates surface issues early, before merge

---

## Networking & Security

- **Ubiquiti UniFi Express 7 router** + 2.5GbE managed switch (VLAN segmentation)
- **Cloudflare Integration**
    - All external services proxied through Cloudflare (DDoS protection, TLS, Zero Trust)
    - Automated certificate management via Cloudflare API

- **Ingress & DNS** – Nginx Proxy Manager, dual AdGuard Home DNS servers
- **Remote Access** – WireGuard VPN, strict firewall + per-service port rules

👉 [Full security documentation](./SECURITY.md)

---

## Storage & Backups

- **ZFS NVMe pools** on each node → snapshots + HA replication
- **Synology DS423+ NAS** (2×12TB HDD SHR + dual NVMe SSD)
    - NFS for large media / raw storage
    - Multi-tier backup pipeline:
        1. Proxmox snapshots → NAS
        2. NAS → Cloud (Google Drive / OneDrive) + local SSD

- **Cloudflare R2** → app/DB backup storage

_Homelab Dashboard:_
![Homepage Dashboard](assets/Homelab.jpeg)

---

## Design Principles

- **Resilient by default** – HA cluster, replication, automated failover
- **Security-first** – VLAN isolation, Zero Trust, VPN ingress, firewall rules
- **Cloud-centric** – mirrors enterprise HA/DR patterns, integrates with Cloudflare + cloud storage
- **Scalable & automated** – GitOps, CI/CD, webhook builds, auto-updates

---

## Outcomes

This homelab proves I can:

- Build and operate **production-like infrastructure**
- Apply **modern DevOps practices** (GitOps, CI/CD, IaC, observability)
- Secure and monitor complex systems with **alerts, logs, and dashboards**
- Manage **resilient deployments** with disaster recovery baked in

It reflects the **engineering mindset** needed in Site Reliability / DevOps: systems that are **resilient, observable, automated, and secure**.

---

## Services & Stacks

Here’s a quick overview (full configs in [`stacks/`](stacks/)):

| Stack             | Services (examples)                                                  | Purpose / Keywords                         |
| ----------------- | -------------------------------------------------------------------- | ------------------------------------------ |
| **dns**           | AdGuard Home, adguardhome-sync                                       | DNS filtering, redundancy                  |
| **reverse-proxy** | Nginx Proxy Manager                                                  | TLS, ingress, Cloudflare API integration   |
| **wireguard**     | WG-Easy                                                              | VPN server, secure remote access           |
| **utilities**     | Beszel, Uptime Kuma, Dozzle, IT-Tools, LibreTranslate, OpenSpeedTest | Monitoring, logs, internal tooling         |
| **vaultwarden**   | Vaultwarden + backup                                                 | Secrets mgmt, encrypted scheduled backups  |
| **media**         | Plex, Sonarr, Radarr, Overseerr, Prowlarr, Tdarr, Recyclarr          | Media automation, GPU/VA-API transcoding   |
| **media-vpn**     | Gluetun, qBittorrent                                                 | VPN-protected egress, health-gated startup |
| **mariadb**       | MariaDB, phpMyAdmin                                                  | Relational DB + admin UI                   |
| **kestra**        | Kestra, Postgres                                                     | Workflow orchestration, job automation     |
| **openweb-ui**    | OpenWeb-UI, SearxNG                                                  | Local LLM interface + meta search          |
| **homepage**      | getHomepage                                                          | Single-pane dashboard                      |

---

## Planned Additions

- **Infrastructure as Code** – Terraform modules and Ansible playbooks for Proxmox and AWS

---

## Repo Structure

```bash
stacks/
  ├── dns/               # DNS stack
  ├── media/             # Plex + automation
  ├── media-vpn/         # VPN-protected egress
  ├── reverse-proxy/     # Nginx Proxy Manager
  ├── utilities/         # Monitoring & tools
  ├── vaultwarden/       # Secrets vault + backup
  ├── wireguard/         # VPN
  ├── kestra/            # Workflow orchestration
  ├── mariadb/           # Database stack
  ├── openweb-ui/        # Local LLM + search
  └── homepage/          # Dashboard
```

Each directory includes:

- `docker-compose.yaml` – services & configs
- `stack.env.example` – reproducible environment variables

---
