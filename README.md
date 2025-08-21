# Homelab Stacks

This repository contains the configuration of my self-hosted homelab, running on **Proxmox** with multiple LXC containers.
Each stack is deployed via **Portainer** using Docker Compose, with configuration managed in Git for reproducibility.

## Structure

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

- Each directory = one **stack** (a group of related services).
- `docker-compose.yaml` = services definition.
- `stack.env.example` = example environment variables for reproducibility (real secrets are stored securely in Portainer / host).

## Workflow

- **Code & Config**: Stored in this repo (GitHub).
- **Deployment**: Portainer Git Stacks syncs directly from GitHub.
- **Secrets**: Managed via Portainer secrets / env injection (not committed).
- **Cluster Mgmt**: Proxmox provides VM/LXC orchestration and storage.
