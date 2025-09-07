# Homelab Kubernetes Production Setup

A step-by-step reference showing how this cluster was made **highly
available, persistent, and observable**. The instructions below reflect
the configuration that is running in the environment today.

> **Quick links:**  
> • [Create LAN wildcard cert (mkcert)](#a-create-a-lan-only-wildcard-cert-with-mkcert-example-uses-macbook)  
> • [Upload cert to Nginx Proxy Manager (NPM)](#b-upload-the-cert-to-nginx-proxy-manager-npm)

---

## 0) Assumptions

- Cluster: kubeadm, 3× control-plane + 3× workers (✅)
- CNI: Flannel (✅)
- TLS termination at **Nginx Proxy Manager (NPM)** outside the cluster ([cert setup](#b-upload-the-cert-to-nginx-proxy-manager-npm))  
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

## 5) Prometheus + Grafana

This deploys kube-prometheus-stack with:

- **Grafana → PostgreSQL** (no SQLite on PVC)
- **Prometheus → Longhorn PVC** (7-day retention)
- **Alertmanager → Longhorn PVC**
- Ingress via **ingress-nginx**, fronted by NPM (HTTP between NPM <-> ingress)

### Prerequisites

- Longhorn is default StorageClass and healthy
- ingress-nginx LB IP (MetalLB) is `10.0.10.240`
- Namespace: `monitoring`

### A) Create secrets

`~/cluster-src/monitoring/postgres-auth-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: postgres-auth
    namespace: monitoring
type: Opaque
stringData:
    POSTGRES_DB: grafana
    POSTGRES_USER: grafana
    POSTGRES_PASSWORD: ChangeMe1234
```

`~/cluster-src/monitoring/grafana-db-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: grafana-db
    namespace: monitoring
type: Opaque
stringData:
    GF_DATABASE_PASSWORD: ChangeMe1234
```

Apply:

```bash
kubectl apply -f ~/cluster-src/monitoring/postgres-auth-secret.yaml
kubectl apply -f ~/cluster-src/monitoring/grafana-db-secret.yaml
```

### B) Deploy PostgreSQL (StatefulSet on Longhorn)

`~/cluster-src/monitoring/postgres.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
    name: postgres
    namespace: monitoring
spec:
    clusterIP: None
    ports:
        - name: pg
          port: 5432
          targetPort: 5432
    selector:
        app: postgres
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
    name: postgres
    namespace: monitoring
spec:
    serviceName: postgres
    replicas: 1
    selector:
        matchLabels:
            app: postgres
    template:
        metadata:
            labels:
                app: postgres
        spec:
            terminationGracePeriodSeconds: 60
            securityContext:
                fsGroup: 999
                fsGroupChangePolicy: "OnRootMismatch"
            initContainers:
                - name: init-perms
                  image: busybox:1.36
                  command:
                      - sh
                      - -lc
                      - >
                          mkdir -p /vol/pgdata &&
                          chown -R 999:999 /vol/pgdata
                  volumeMounts:
                      - name: data
                        mountPath: /vol
            containers:
                - name: postgres
                  image: postgres:16
                  securityContext:
                      runAsUser: 999
                      runAsGroup: 999
                  ports:
                      - name: pg
                        containerPort: 5432
                  envFrom:
                      - secretRef:
                            name: postgres-auth
                  env:
                      - name: PGDATA
                        value: /var/lib/postgresql/data
                  volumeMounts:
                      - name: data
                        mountPath: /var/lib/postgresql/data
                        subPath: pgdata
                  readinessProbe:
                      exec:
                          command: ["sh", "-lc", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
                      initialDelaySeconds: 10
                      periodSeconds: 5
                  livenessProbe:
                      exec:
                          command: ["sh", "-lc", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
                      initialDelaySeconds: 20
                      periodSeconds: 10
                  resources:
                      requests:
                          cpu: "100m"
                          memory: "256Mi"
    volumeClaimTemplates:
        - metadata:
              name: data
          spec:
              accessModes: ["ReadWriteOnce"]
              storageClassName: longhorn
              resources:
                  requests:
                      storage: 5Gi
```

Apply & wait:

```bash
kubectl apply -f ~/cluster-src/monitoring/postgres.yaml
kubectl -n monitoring rollout status sts/postgres
```

### C) Helm values for kube-prometheus-stack

`~/cluster-src/monitoring/values.yaml`

```yaml
grafana:
    env:
        GF_SERVER_ROOT_URL: http://grafana.homelab.local/
    persistence:
        enabled: false
    grafana.ini:
        session:
            provider: database
        database:
            type: postgres
            host: postgres.monitoring.svc.cluster.local:5432
            name: grafana
            user: grafana
            ssl_mode: disable
    envFromSecret: grafana-db
    ingress:
        enabled: true
        ingressClassName: nginx
        hosts: ["grafana.homelab.local"]
        path: /

prometheus:
    prometheusSpec:
        retention: 7d
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
        hosts: ["prometheus.homelab.local"]
        paths: ["/"]

alertmanager:
    alertmanagerSpec:
        storage:
            volumeClaimTemplate:
                spec:
                    storageClassName: longhorn
                    resources:
                        requests:
                            storage: 2Gi
```

Install/upgrade:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f ~/cluster-src/monitoring/values.yaml
```

### D) Ingress + NPM

- NPM Proxy Hosts:
    - **grafana.homelab.local** → `http://10.0.10.240:80`
    - **prometheus.homelab.local** → `http://10.0.10.240:80`
- LAN DNS rewrite for **\*.homelab.local** points both hostnames to the **NPM** IP.

### E) Verification

```bash
kubectl -n monitoring get pods,pvc,ingress

# Expect postgres in Running and grafana showing postgres, not sqlite:
kubectl -n monitoring logs deploy/monitoring-grafana | egrep -i 'dbtype|postgres|sqlite'

# External checks
curl -sS http://grafana.homelab.local/api/health | jq .
curl -sS http://prometheus.homelab.local/-/ready
```

### F) Cleanup (if migrating from SQLite)

If a legacy Grafana PVC exists, delete it now:

```bash
kubectl -n monitoring get pvc
```

If it exists:

```bash
kubectl -n monitoring delete pvc monitoring-grafana --ignore-not-found
```

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
- Either:
    - Choose "None" as the **TLS certificate**
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

### A) Create a LAN-only wildcard cert with `mkcert` (example uses MacBook)

```bash
# trust a local CA on MacBook (system/Firefox/Java)
mkcert -install

# issue a wildcard cert for your LAN domain
mkcert "*.homelab.local"

# outputs (examples):
#   _wildcard.homelab.local.pem        <- certificate
#   _wildcard.homelab.local-key.pem    <- private key
```

### B) Upload the cert to **Nginx Proxy Manager** (NPM)

- NPM → **SSL Certificates** → **Add SSL Certificate** → **Custom**
    - **Name:** `*.homelab.local`
    - **Certificate Key:** upload `_wildcard.homelab.local-key.pem`
    - **Certificate:** upload `_wildcard.homelab.local.pem`
    - Save.

### C) Create the Argo CD Ingress (TLS stays at NPM)

```bash
mkdir -p ~/cluster-src/argocd
cat > ~/cluster-src/argocd/argocd-ingress.yaml <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"   # ingress -> service over HTTPS (avoids 80->443 redirects)
    nginx.ingress.kubernetes.io/ssl-redirect: "false"       # TLS terminates at NPM
    nginx.ingress.kubernetes.io/proxy-real-ip-cidr: "10.0.10.0/24"  # adjust to your LAN
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
YAML

# install Argo CD if not already present
kubectl create ns argocd 2>/dev/null || true
kubectl -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# apply ingress
kubectl apply -f ~/cluster-src/argocd/argocd-ingress.yaml
```

### D) Configure the NPM Proxy Host

- **Hosts → Add Proxy Host**
    - **Domain Names:** `argocd.homelab.local`
    - **Scheme:** `http`
    - **Forward Hostname/IP:** `<INGRESS_LB_IP>` (e.g. `10.0.10.240`)
    - **Forward Port:** `80`
    - **Enable**: _Block Common Exploits_, _Websockets Support_
    - **SSL tab:** select your custom cert `*.homelab.local`
        - Force SSL
        - HSTS Enabled
        - HTTP/2 Support
    - Save.

### E) Verify & first login

```bash
# verify K8s objects
kubectl -n argocd get ingress
kubectl -n argocd get svc argocd-server

# get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
# username: admin
```

Open `https://argocd.homelab.local` in your browser (your MacBook already trusts the mkcert CA).

> **CLI note (simple path):** For `argocd` CLI without extra ingress tweaks, use a temporary port-forward:
>
> ```bash
> kubectl -n argocd port-forward svc/argocd-server 8080:80
> argocd login localhost:8080 --insecure
> ```
>
> (If you want CLI through NPM later, consider nginx **ssl-passthrough** or a dedicated gRPC ingress/host.)

---

## ✅ Outcome

- **HA control-plane** with kube-vip
- **LoadBalancer IPs** via MetalLB (`10.0.10.240` for ingress-nginx)
- **HA storage** via Longhorn
- **Backups:** etcd snapshots + Longhorn backups (NAS)
- **Observability:** Grafana on **Postgres**, Prometheus on **Longhorn**, both via ingress/NPM
- **GitOps:** Argo CD
