# Homelab Kubernetes Production Setup

A step-by-step reference showing how this cluster was made **highly
available, persistent, and observable**. The instructions below reflect
the configuration that is running in the environment today.

---

## 0) Assumptions

- Cluster: kubeadm, 3× control-plane + 3× workers (✅)
- CNI: Flannel (✅)
- TLS termination at **Nginx Proxy Manager (NPM)** outside the cluster  
  → In-cluster **NGINX Ingress Controller** + **MetalLB** provide ingress and LoadBalancer IPs; TLS terminates at NPM.

## Network & Edge Access Model

```text
                ┌───────────────────────┐
                │      Cloudflare       │
                │ Proxy + DNS (A/CNAME) │
                └──────────┬────────────┘
                           │
             *.example.com → Public Static IP
                           │
                    (Port 443 only)
                           │
                  ┌────────▼─────────┐
                  │    Router/NAT    │
                  └────────┬─────────┘
                           │
                ┌──────────▼────────────┐
                │ Nginx Proxy Manager   │  (Proxmox LXC)
                │ - TLS termination     │
                │ - Cloudflare API certs│
                │ - Auth (select apps)  │
                └──────────┬────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
      ┌───────▼──────────┐       ┌──────▼──────────┐
      │ K8s Ingress      │       │ Direct services │
      │ (NGINX + MetalLB)│       │ (VPN, Mail, etc)│
      │ Routes to Pods   │       │ Bypass NPM LB   │
      └──────────────────┘       └─────────────────┘
```

---

## kube-vip (control-plane VIP) on kubeadm (3 masters + 3 workers)

> **Goal:** Provide a highly available control-plane VIP at
> `10.0.10.200` using kube-vip **static pods** (ARP, control-plane only).  
> **Context:** Cluster is already running (Flannel CNI), containerd,
> kubeadm v1.33.4.

---

### 1) Quick VIP sanity (from master-01)

Check that the VIP is free on the LAN.

```bash
VIP=10.0.10.200
ping -c1 -W1 $VIP || echo "VIP not responding (good)"
```

---

### 2) Generate kube-vip static pod on **master-01**

Write the static pod manifest; kubelet starts it automatically.

```bash
sudo mkdir -p /etc/kubernetes/manifests
export VIP=10.0.10.200
export INTERFACE=eth0
export KVVERSION=v1.0.0

alias kube-vip="sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION; \
  sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"

kube-vip manifest pod \
  --interface $INTERFACE \
  --address $VIP \
  --controlplane \
  --arp \
  --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml

# Verify kube-vip Pod on master-01
kubectl -n kube-system get pods -o wide | grep kube-vip

# Check the VIP bound on this node (OK if leader is elsewhere)
ip addr show eth0 | grep 10.0.10.200 || echo "VIP not on this node (that can be OK if another master is leader)"
```

---

### 3) Enable kube-vip RBAC (once, from any master; ran on master-01)

```bash
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml
```

---

### 4) Generate kube-vip static pod on **master-02** and **master-03**

Run the same commands on each of the other masters.

**On master-02:**

```bash
sudo mkdir -p /etc/kubernetes/manifests
export VIP=10.0.10.200
export INTERFACE=eth0
export KVVERSION=v1.0.0
alias kube-vip="sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION; sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"

kube-vip manifest pod \
  --interface $INTERFACE \
  --address $VIP \
  --controlplane \
  --arp \
  --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```

**On master-03:**

```bash
sudo mkdir -p /etc/kubernetes/manifests
export VIP=10.0.10.200
export INTERFACE=eth0
export KVVERSION=v1.0.0
alias kube-vip="sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION; sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"

kube-vip manifest pod \
  --interface $INTERFACE \
  --address $VIP \
  --controlplane \
  --arp \
  --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
```

Verify all three kube-vip Pods:

```bash
kubectl -n kube-system get pods -o wide | grep kube-vip
```

---

### 5) Create kubeadm HA config (on **master-01**)

Define the VIP endpoint and API SANs for all masters.

```bash
sudo tee /root/kubeadm-ha.yaml >/dev/null <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.33.4
clusterName: kubernetes
controlPlaneEndpoint: 10.0.10.200:6443
apiServer:
  certSANs:
    - 10.0.10.160   # master-01
    - 10.0.10.161   # master-02
    - 10.0.10.162   # master-03
    - 10.0.10.200   # VIP
    - k8s-master-01
    - k8s-master-02
    - k8s-master-03
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
etcd:
  local: { dataDir: /var/lib/etcd }
EOF

# (Optional) View the file
sudo cat /root/kubeadm-ha.yaml
```

---

### 6) Rotate API certs + kubeconfigs to use the VIP — **master-01**

Execute on one master at a time; wait until it is Ready before moving on.

```bash
# Rotate apiserver cert to include VIP/DNS
sudo mv /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.bak.$(date +%s)
sudo mv /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.key.bak.$(date +%s)
sudo kubeadm init phase certs apiserver --config /root/kubeadm-ha.yaml

# Regenerate kubeconfigs that point at the VIP
for f in admin.conf controller-manager.conf scheduler.conf kubelet.conf; do
  [ -f /etc/kubernetes/$f ] && sudo mv /etc/kubernetes/$f /etc/kubernetes/$f.bak.$(date +%s)
done
sudo kubeadm init phase kubeconfig all --config /root/kubeadm-ha.yaml

# Restart kubelet to pick up new configs
sudo systemctl restart kubelet

# Refresh kubectl context for your user (optional)
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify node health + cert SANs + kubeconfig server = VIP
kubectl get nodes -o wide
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A1 "Subject Alternative Name"
sudo grep 'server:' -n /etc/kubernetes/admin.conf
```

---

### 7) Repeat cert/kubeconfig rotation — **master-02**

Run after master-01 is healthy.

```bash
# Write config again
sudo tee /root/kubeadm-ha.yaml >/dev/null <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.33.4
clusterName: kubernetes
controlPlaneEndpoint: 10.0.10.200:6443
apiServer:
  certSANs:
    - 10.0.10.160
    - 10.0.10.161
    - 10.0.10.162
    - 10.0.10.200
    - k8s-master-01
    - k8s-master-02
    - k8s-master-03
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
etcd:
  local: { dataDir: /var/lib/etcd }
EOF

sudo mv /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.bak.$(date +%s)
sudo mv /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.key.bak.$(date +%s)
sudo kubeadm init phase certs apiserver --config /root/kubeadm-ha.yaml

for f in admin.conf controller-manager.conf scheduler.conf kubelet.conf; do
  [ -f /etc/kubernetes/$f ] && sudo mv /etc/kubernetes/$f /etc/kubernetes/$f.bak.$(date +%s)
done
sudo kubeadm init phase kubeconfig all --config /root/kubeadm-ha.yaml
sudo systemctl restart kubelet

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes -o wide
sudo grep 'server:' -n /etc/kubernetes/admin.conf
```

---

### 8) Repeat cert/kubeconfig rotation — **master-03**

Run after master-02 is healthy.

```bash
# Write config again
sudo tee /root/kubeadm-ha.yaml >/dev/null <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.33.4
clusterName: kubernetes
controlPlaneEndpoint: 10.0.10.200:6443
apiServer:
  certSANs:
    - 10.0.10.160
    - 10.0.10.161
    - 10.0.10.162
    - 10.0.10.200
    - k8s-master-01
    - k8s-master-02
    - k8s-master-03
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
etcd:
  local: { dataDir: /var/lib/etcd }
EOF

sudo mv /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.bak.$(date +%s)
sudo mv /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.key.bak.$(date +%s)
sudo kubeadm init phase certs apiserver --config /root/kubeadm-ha.yaml

for f in admin.conf controller-manager.conf scheduler.conf kubelet.conf; do
  [ -f /etc/kubernetes/$f ] && sudo mv /etc/kubernetes/$f /etc/kubernetes/$f.bak.$(date +%s)
done
sudo kubeadm init phase kubeconfig all --config /root/kubeadm-ha.yaml
sudo systemctl restart kubelet

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes -o wide
sudo grep 'server:' -n /etc/kubernetes/admin.conf
```

---

### 9) External VIP test (from a client machine)

```bash
curl -k https://10.0.10.200:6443/version
uname -a
```

---

### 10) Final checks (from any kubectl)

```bash
kubectl -n kube-system get pods -o wide | grep kube-vip
kubectl get nodes -o wide
```

---

## 2) MetalLB (LoadBalancer IPs)

### Install

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
kubectl create ns metallb-system
helm install metallb metallb/metallb -n metallb-system
```

### Create the pool & L2Advertisement (run on master-01)

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.10.240-10.0.10.254   # dedicated to MetalLB
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - homelab-pool
YAML

# sanity: CRDs exist and objects are created
kubectl -n metallb-system get ipaddresspools,l2advertisements
```

### Quick test that MetalLB assigns an IP

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create ns ingress-nginx
helm install ingress ingress-nginx/ingress-nginx -n ingress-nginx \
  --set controller.replicaCount=2 \
  --set controller.service.type=LoadBalancer

# watch for an External IP from 10.0.10.240–10.0.10.254
kubectl -n ingress-nginx get svc ingress-ingress-nginx-controller -w
```

### Wire up Nginx Proxy Manager (when using ingress-nginx)

- In NPM, create Proxy Hosts pointing to:

    **<INGRESS_EXTERNAL_IP>**:80 (TLS terminates at NPM, HTTP to cluster).

### Verify MetalLB health

```bash
kubectl -n metallb-system get pods -o wide
kubectl -n metallb-system logs deploy/metallb-controller | tail -n 50
kubectl -n metallb-system logs ds/metallb-speaker | tail -n 50
```

---

## 3) Longhorn (HA Storage)

### Check prerequisites (on all workers)

Download the Longhorn CLI:

```bash
# AMD64
curl -sSfL -o longhornctl https://github.com/longhorn/cli/releases/download/v1.9.1/longhornctl-linux-amd64

# ARM64
curl -sSfL -o longhornctl https://github.com/longhorn/cli/releases/download/v1.9.1/longhornctl-linux-arm64

chmod +x longhornctl
```

Run preflight checks:

```bash
# Verify prerequisites
./longhornctl --kube-config ~/.kube/config check preflight

# Install missing prerequisites
./longhornctl --kube-config ~/.kube/config install preflight
```

For other installation options, see the [Longhorn Quick Installation Guide](https://longhorn.io/docs/1.9.1/deploy/install/).

---

### Install Longhorn

```bash
# Add repo & install
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm install longhorn longhorn/longhorn \
  -n longhorn-system --create-namespace
```

---

(Optional) limit replicas for the Longhorn UI:

```bash
mkdir -p ~/cluster-src/longhorn-system
cd ~/cluster-src/longhorn-system

cat <<'EOF' > longhorn-values.yaml
longhornUI:
  replicas: 1
EOF
```

Install (or upgrade) using the custom values:

```bash
# Add repo & install
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install (or upgrade if already installed) using the custom values file
helm upgrade --install longhorn longhorn/longhorn \
  -n longhorn-system --create-namespace \
  -f ./longhorn-values.yaml
```

---

Check pods:

```bash
kubectl -n longhorn-system get pods
```

---

### Access the Longhorn UI

Longhorn UI requires an Ingress controller. Authentication is not enabled by default.  
See the [Ingress guide](https://longhorn.io/docs/1.9.1/deploy/accessing-the-ui/longhorn-ingress) for NGINX + basic auth setup.

Check services:

```bash
kubectl -n longhorn-system get svc
```

Example output:

```txt
NAME                TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
longhorn-backend    ClusterIP   10.20.248.250    <none>        9500/TCP  58m
longhorn-frontend   ClusterIP   10.20.245.110    <none>        80/TCP    58m
```

---

### Assign a static External IP (MetalLB)

Check for available IPs:

```bash
INUSE="$(kubectl get svc -A -o jsonpath='{range .items[*]}{.status.loadBalancer.ingress[*].ip}{" "}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')"; \
kubectl get ipaddresspools -n metallb-system -o jsonpath='{.items[*].spec.addresses[*]}' \
| tr ' ' '\n' \
| awk -v INUSE="$INUSE" 'BEGIN{
  printf "%-16s  %-8s  %s\n","IP","STATUS","OWNER";
  printf "%-16s  %-8s  %s\n","----------------","--------","-----------------------------";
  n=split(INUSE, ln, "\n");
  for (i=1;i<=n;i++){
    if (ln[i]=="") continue;
    split(ln[i], a, " ");
    if (a[1]!="") owner[a[1]]=a[2];
  }
}
{
  if ($0=="") next;
  split($0, parts, "-");
  if (length(parts)!=2) next;                 # only dash-style ranges
  split(parts[1], s, ".");
  split(parts[2], e, ".");
  if (s[1]"."s[2]"."s[3] != e[1]"."e[2]"."e[3]) {
    # skip non-/24 ranges in this minimal version
    next;
  }
  base=s[1]"."s[2]"."s[3];
  for (i=s[4]; i<=e[4]; i++){
    ip=base"."i;
    if (ip in owner) {
      printf "%-16s  %-8s  %s\n", ip, "TAKEN", owner[ip];
    } else {
      printf "%-16s  %-8s  %s\n", ip, "FREE", "-";
    }
  }
}'
```

Pick an IP from the MetalLB pool, then patch the service:

```bash
kubectl -n longhorn-system patch svc longhorn-frontend \
  -p '{"spec":{"loadBalancerIP":"10.0.10.241"}}'
```

---

### Check if Longhorn is the default StorageClass

```bash
kubectl get storageclass
```

---

## 4) Backups (etcd + Longhorn on Synology NAS NFS)

### Goal

- **etcd snapshots** saved off-cluster (to Synology NAS).
- **Longhorn PVC backups** automatically written to the same NAS.
- Disaster recovery ready: restore both control-plane + app data.

---

### A) Synology NAS setup

0. **Enable NFS service (global)**
    - DSM → **Control Panel → File Services → NFS**
    - **Enable NFS service** ✅
    - **Maximum NFS protocol:** **NFSv4.1** (recommended)

1. **Create shared folder** (via DSM):
    - Name: `k8s-backups`
    - Location: `/volume1/k8s-backups`
    - Enable **NFS** (Control Panel → Shared Folder → Edit → NFS Permissions).

2. **NFS Permissions**:
    - Allowed hosts: `10.0.10.0/24` (homelab VLAN).
    - Privileges: `Read/Write`.
    - Squash: `No mapping` (or `Map all users to admin`).
    - Security: `sys`.

3. **Apply settings**.
    - Synology exposes a path like:
        ```
        10.0.10.<NAS_IP>:/volume1/k8s-backups
        ```

---

### B) Mount NFS on control-plane nodes (for etcd snapshots)

On each master (`k8s-master-01`, `k8s-master-02`, `k8s-master-03`):

```bash
# Install NFS client tools, cron, and etcdctl
sudo apt-get update && sudo apt-get install -y nfs-common cron etcd-client
sudo systemctl enable --now cron

# Create local mountpoint
sudo mkdir -p /mnt/k8s-backups

# Mount Synology NFS share
sudo mount -t nfs 10.0.10.<NAS_IP>:/volume1/k8s-backups /mnt/k8s-backups

# Persist across reboots
echo "10.0.10.<NAS_IP>:/volume1/k8s-backups /mnt/k8s-backups nfs defaults 0 0" | sudo tee -a /etc/fstab
```

---

### C) etcd snapshots to NAS

Test a snapshot on a master:

```bash
# Save snapshot to NAS-mounted path
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /mnt/k8s-backups/etcd-snapshot-$(date +%Y%m%d-%H%M).db
```

Verify the file exists in `/mnt/k8s-backups`.

#### Automate with cron

```bash
sudo tee /usr/local/sbin/etcd-snapshot.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

OUT="/mnt/k8s-backups/etcd-snapshot-$(date +%Y%m%d-%H%M).db"
/usr/bin/env ETCDCTL_API=3 /usr/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save "$OUT"

# prune older than 7 days
find /mnt/k8s-backups -maxdepth 1 -type f -name 'etcd-snapshot-*.db' -mtime +7 -delete
EOF

sudo chmod +x /usr/local/sbin/etcd-snapshot.sh
```

Edit root’s crontab (`sudo crontab -e`):

```
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * * /usr/local/sbin/etcd-snapshot.sh
```

Check the NAS folder from NAS or via CLI:

```bash
ls -lh /mnt/k8s-backups
```

---

### D) Longhorn backups to NAS

1. Open **Longhorn UI**.
2. Go to **Settings → Backup Target**.
3. Set to the NFS share:
    ```
    nfs://10.0.10.<NAS_IP>:/volume1/k8s-backups/longhorn
    ```
4. Leave **Backup Target Credential Secret** empty (NFS does not require it).
5. Test a PVC backup:
    - Create a PVC-backed pod, write data, then use **Longhorn → Volume → Create Backup**.
    - Verify files appear in `k8s-backups/longhorn` on the NAS.

---

### E) (Optional) Velero with MinIO on NFS

To capture cluster resources + PVCs:

1. Deploy **MinIO** inside Kubernetes.
2. Point MinIO’s dataDir at the NAS (`/volume1/k8s-backups/minio`).
3. Install **Velero** using MinIO as S3 target.

Velero backs up **resources + PVCs** in one command, while Longhorn handles
volume snapshots underneath.

---

### ✅ Verification

- From a master:

    ```bash
    ls -lh /mnt/k8s-backups/
    ```

    → should show etcd snapshots.

- From Synology DSM: `etcd-snapshot-*` and `longhorn/` directories
  should exist.

- From Longhorn UI: backups should list PVC backups stored on NFS.

---

## 5) Prometheus + Grafana (kube-prometheus-stack)

This section pins persistence to **Longhorn**, exposes **Ingress** for NPM,
and includes quick verification steps.

---

### Prerequisites

- Kubernetes cluster up (✅)
- MetalLB installed (✅) — ingress-nginx LB IP: `10.0.10.240`
- ingress-nginx installed (✅)
- Longhorn installed and **default** StorageClass (✅)
- Helm repos updated (✅)

---

### 1) Add Helm repo

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Optional check:

```bash
helm search repo prometheus-community/kube-prometheus-stack
```

---

### 2) Create values file (persistence + ingress)

```bash
mkdir -p ~/cluster-src/monitoring
cat > ~/cluster-src/monitoring/values.yaml <<'YAML'
grafana:
  persistence:
    enabled: true
    storageClassName: longhorn
    size: 5Gi
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts: [ "grafana.homelab.local" ]
    path: /
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          resources:
            requests:
              storage: 5Gi
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts: [ "prometheus.homelab.local" ]
    paths: [ "/" ]
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          resources:
            requests:
              storage: 2Gi
YAML
```

---

### 3) Install / upgrade the stack

```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f ~/cluster-src/monitoring/values.yaml
```

Expect `STATUS: deployed`.

---

### 4) Verify resources

```bash
# Pods should become Running
kubectl -n monitoring get pods

# PVCs should be Bound on Longhorn
kubectl -n monitoring get pvc -o wide

# Ingresses created by the chart
kubectl -n monitoring get ingress
```

Expected:

- Grafana and Prometheus pods in `Running`
- PVCs bound with StorageClass `longhorn`
- Ingress hosts:
    - `grafana.homelab.local`
    - `prometheus.homelab.local`

---

### 5) Wire through Nginx Proxy Manager (NPM)

Create **two Proxy Hosts** in NPM, both pointing to the
**ingress-nginx** IP:

- **grafana.homelab.local** → `http://10.0.10.240:80`
- **prometheus.homelab.local** → `http://10.0.10.240:80`

Per-host settings:

- SSL: a certificate (Force SSL: on)
- Websockets: on (helps Grafana)

Ensure LAN DNS points both hostnames to **NPM’s IP**.

---

### 6) First Grafana login

```bash
kubectl -n monitoring get secret prometheus-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
# user: admin
```

Open https://grafana.homelab.local → log in → Dashboards.  
(Or http://grafana.homelab.local if no cert was used.)

---

### 7) Troubleshooting

- **Ingress unreachable**: confirm ingress-nginx Service has an
  External IP (`10.0.10.240`) and NPM forwards to `:80`.
- **PVC Pending**: ensure `longhorn` is default and Longhorn is healthy.
- **Grafana redirects**: set
  `grafana.env.GF_SERVER_ROOT_URL=https://grafana.homelab.local/`
  and upgrade.

---

### 8) Upgrades later

```bash
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring -f ~/cluster-src/monitoring/values.yaml
```

Prometheus & Grafana run persistently behind a single ingress IP,
fronted by NPM with TLS.

---

## 6) Expose Longhorn UI via Ingress (single entry IP)

Expose Longhorn behind the existing **ingress-nginx** LoadBalancer
(`10.0.10.240`), accessed through Nginx Proxy Manager (NPM) with TLS/auth,
reusing the same entry IP as Grafana/Prometheus.

---

### 1) Ensure Longhorn frontend is ClusterIP

If `longhorn-frontend` was previously patched with a `loadBalancerIP`,
revert it to ClusterIP:

```bash
kubectl -n longhorn-system patch svc longhorn-frontend \
  -p '{"spec":{"type":"ClusterIP","loadBalancerIP":null}}'
```

Confirm:

```bash
kubectl -n longhorn-system get svc longhorn-frontend
```

Output should show `TYPE: ClusterIP`.

---

### 2) Create Longhorn Ingress

Create a YAML file:

```bash
cat <<'EOF' > ~/cluster-src/longhorn-system/longhorn-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
spec:
  ingressClassName: nginx
  rules:
  - host: longhorn.homelab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: longhorn-frontend
            port:
              number: 80
EOF
```

Apply it:

```bash
kubectl apply -f ~/cluster-src/longhorn-system/longhorn-ingress.yaml
```

Ingress should show an address (the ingress-nginx LB IP 10.0.10.240):

```bash
kubectl -n longhorn-system get ingress longhorn-ingress
```

---

### 3) Configure DNS or host entry

Point DNS (or `/etc/hosts`) to the **ingress-nginx LB IP**:

```txt
10.0.10.240   longhorn.homelab.local
```

---

### 4) Add host in Nginx Proxy Manager

- **Domain Names:** `longhorn.homelab.local`
- **Scheme:** `http`
- **Forward Hostname/IP:** `10.0.10.240`
- **Forward Port:** `80`
- Enable **Block Common Exploits**
- Enable **Websockets Support**
- Add **TLS certificate** (Let’s Encrypt or custom)
- (Optional) Attach an **Access List** for authentication.

---

### 5) Verify

Open a browser:

```
https://longhorn.homelab.local
```

(Or `http://longhorn.homelab.local` if no cert was used.)

The Longhorn UI should be proxied through NPM, using the same
ingress-nginx IP as other cluster services.

---

Now Longhorn, Grafana, and Prometheus are all behind a single IP,
secured consistently through NPM.

---

## 7) Argo CD (GitOps)

### Ingress

```bash
mkdir -p ~/cluster-src/argocd
nano ~/cluster-src/argocd/argocd-ingress.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
    name: argocd
    namespace: argocd
    annotations:
        nginx.ingress.kubernetes.io/backend-protocol: "HTTPS" # ingress → service over HTTPS
        nginx.ingress.kubernetes.io/ssl-redirect: "false" # NPM terminates TLS; keep HTTP between NPM and ingress
        nginx.ingress.kubernetes.io/proxy-real-ip-cidr: "10.0.10.0/24" # optional: tighten from 0.0.0.0/0
spec:
    ingressClassName: nginx
    rules:
        - host: argocd.homelab.local
          http:
              paths:
                  - path: /
                    pathType: Prefix
                    backend:
                        service:
                            name: argocd-server
                            port:
                                number: 443
```

### Install

```bash
# Install Argo CD (if not already present)
kubectl create ns argocd
kubectl -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Apply ingress
kubectl apply -f ~/cluster-src/argocd/argocd-ingress.yaml

# Verify
kubectl -n argocd get ingress
kubectl -n argocd get svc argocd-server
```

### NPM

- Add `argocd.homelab.local` → Ingress IP port 80 with TLS
  (attach a certificate for HTTPS).

### Initial login

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
# username: admin
```

---

# ✅ Outcome

- **HA control-plane** with VIP
- **LoadBalancer IPs** for services
- **HA storage** via Longhorn
- **Backups:** etcd snapshots + Velero
- **Ingress with TLS** (via NPM)
- **Observability:** Grafana + Prometheus exposed
- **GitOps:** Argo CD managing workloads
