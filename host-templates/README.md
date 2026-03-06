# host-templates/

Reusable Docker Compose templates deployed directly on individual LXC containers
and VMs — outside of Portainer GitOps.

Copy the relevant template to the host, fill in the required environment variables,
and run with `docker compose up -d`.

## Templates

### `agents/` — Baseline monitoring and management stack

Deployed on every LXC/VM in the fleet. Provides:

- `beszel-agent` — system metrics (CPU, memory, disk, network, GPU, temperatures)
- `portainer-agent` — centralized Docker management via Portainer
- `dozzle-agent` — log aggregation across all hosts
- `dockerproxy` — read-only Docker socket proxy (secure API access for Homepage, etc.)
- `watchtower` — automated image updates with Slack reporting

### `nodes/` — Tdarr transcoding node

Deployed on dedicated transcoding LXCs (`ct-tdarr-node-01`, `ct-tdarr-node-02`).
Connects back to the Tdarr server in the `media` stack and uses Intel VA-API for
GPU-accelerated transcoding.
