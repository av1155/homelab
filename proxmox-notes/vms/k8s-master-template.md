# Kubernetes Control Plane Setup on Proxmox VM

This guide walks through preparing a Proxmox VM for Kubernetes, setting up a static IP, initializing the control-plane node, and installing Flannel networking.

---

## Kubernetes Cluster Hardware HA

### Masters (3 nodes)

- **CPU**: 2 vCPUs each
- **RAM**: 4 GB each
- **Role**: Control-plane + etcd

### Workers (3 nodes)

- **CPU**: 2 vCPUs each
- **RAM**: 5 GB each
- **Role**: Application workloads (pods/services)

---

## Configure Networking with Netplan

Install a text editor:

```bash
sudo apt install -y nano
```

Navigate to the Netplan config directory:

```bash
cd /etc/netplan
ls
```

Back up your configuration file (replace the filename if different):

```bash
sudo cp 50-cloud-init.yaml 50-cloud-init.yaml.bak
```

Edit the file:

```bash
sudo nano 50-cloud-init.yaml
```

### Example Netplan Configuration

⚠️ YAML is indentation-sensitive. Below is an example of setting a static IP.

- `10.0.10.1` → your gateway
- `10.0.10.160/24` → the IP for this VM
- `eth0` → your network interface name

```yaml
network:
    version: 2
    ethernets:
        eth0:
            addresses:
                - 10.0.10.160/24
            nameservers:
                addresses:
                    - 10.0.10.1
            routes:
                - to: default
                  via: 10.0.10.1
```

Apply the changes:

```bash
sudo netplan try
```

If you lose connection, ssh to the new IP, or reboot the VM via the Proxmox GUI and reconnect using the new IP.

---

## Initialize Kubernetes Control Plane

Run the following command (replace placeholders with your values):

```bash
sudo kubeadm init \
  --control-plane-endpoint=<CONTROL_NODE_IP> \
  --node-name=<HOSTNAME> \
  --pod-network-cidr=10.244.0.0/16
```

**Example:**

```bash
sudo kubeadm init \
  --control-plane-endpoint=10.0.10.160 \
  --node-name=k8s-master-01 \
  --pod-network-cidr=10.244.0.0/16
```

You should see output like:

```txt
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join additional nodes using the join command shown in the output.

Control-plane nodes:

kubeadm join 10.0.10.160:6443 --token <...> \
        --discovery-token-ca-cert-hash sha256:<...> \
        --control-plane

Worker nodes:

kubeadm join 10.0.10.160:6443 --token <...> \
        --discovery-token-ca-cert-hash sha256:<...>
```

---

**DO NOT JOIN THE NODES YET**

---

## Install Flannel Networking

Check pods:

```bash
kubectl get pods --all-namespaces
```

You’ll likely see some pods pending. Install Flannel:

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

Check again:

```bash
kubectl get pods --all-namespaces
```

All pods should now be running. If not, wait a couple seconds and check again.

---

## Join Worker Nodes

Check the control-plane node status:

```bash
kubectl get nodes
```

Run the join command provided by `kubeadm init` on each worker node.  
If the token has expired, create a new one:

```bash
kubeadm token create --print-join-command
```

---

## Next Steps

At this point:

- Your control-plane node is ready.
- Worker nodes can join the cluster.
- Flannel networking is set up.

From here, you can deploy workloads or add additional components such as:

- [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
- [ingress controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
