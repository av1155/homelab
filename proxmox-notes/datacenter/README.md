# Proxmox Cluster (homelab-cluster)

- Nodes:
    - pve-node-a (10.0.10.NODE-A-IP)
    - pve-node-b (10.0.10.NODE-B-IP)
- QDevice (Raspberry Pi): 10.0.10.PI-IP
- Total votes: 3
- Quorum: 2 required
- Config backed up: /etc/pve/corosync.conf.backup-2025-05-12

---

# Proxmox No-Subscription Popup Patch

**Reference:**
[https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/](https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/)

### Apply Patch (for PVE 8.4+):

```bash
sed -i.backup -z "s/res === null || res === undefined || \!res || res\n\t\t\t.data.status.toLowerCase() \!== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service
```

### Revert Patch:

```bash
apt-get install --reinstall proxmox-widget-toolkit
```

### Alternative Revert (using backup):

```bash
mv /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.backup /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service
```

---

# NFS Mount Setup for Media Share Inside LXC Container (e.g., Plex, Jellyfin)

### 1. On Proxmox Host:

```
mkdir -p /mnt/nas-media
```

Ensure this line is in `/etc/fstab` for persistent NFS mount:

```fstab
<NAS_IP>:/volume1/Media /mnt/nas-media nfs defaults,_netdev,nofail,x-systemd.automount 0 0
```

> Make sure NFS permissions are set on the NAS for that shared folder.

Then, mount it:

```bash
mount -a
```

### 2. In LXC Container Config (`/etc/pve/lxc/<vmid>.conf`):

Use a proper bind mount (DO NOT use `mp0` for NFS):

```conf
lxc.mount.entry: /mnt/nas-media mnt/nas-media none bind,create=dir
```

This ensures the container sees the fully-mounted NFS share.

### 3. Inside Container:

Ensure Docker containers (e.g., Plex) point to `/mnt/nas-media`:

```yaml
volumes:
    - /mnt/nas-media:/media:ro
```

This gives Plex full access to `/media/Movies`, `/media/TV Shows`, etc.

---

# Enable Intel iGPU passthrough for VAAPI/QSV in LXC on Proxmox

On the host run:

```bash
apt update
sed -i -E '/^deb /s/\bmain contrib\b/& non-free non-free-firmware/' /etc/apt/sources.list

apt update
apt install -y intel-media-va-driver-non-free intel-gpu-tools intel-microcode libdrm-intel1 linux-headers-amd64 vainfo

# please reboot node
```

### Enable iGPU access in the LXC config (e.g. /etc/pve/lxc/106.conf):

```bash
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
lxc.hook.pre-start: sh -c "chown 0:108 /dev/dri/renderD128"
```

### Restart the LXC container, and test with:

```bash
vainfo
```

### Enable on Plex Docker Compose File

```
environment:
  - PUID=0
  - PGID=108
  - PLEX_HW_TRANSCODE=1
devices:
  - /dev/dri:/dev/dri
```

---

# Set up alerts in Proxmox

[Set up alerts in Proxmox before it's too late!](https://youtu.be/85ME8i4Ry6A?si=Sc9QSdNjAtNGqWiO)

[Written Guide](https://technotim.live/posts/proxmox-alerts/)

### USE NEW NOTIFICATION METHOD

**DATACENTER > NOTIFICATIONS > NOTIFICATION TARGET > ADD > SMTP**

Then

\*\*DATACENTER > NOTIFICATIONS > NOTIFICATION MATCHERS > ADD

Give it a name, leave the filters as they are, do not touch them, then:

Targets to notify > select the target you created in `Notification Target`

---

# UPS Auto Shutdown with NUT Network Client

[UPS Integration on Proxmox](https://docs.andreaventi.com/guides/04_synology_nas/ups-auto-shutdown.html?h=ups+integration#ups-integration-auto-shutdown)

Set up NUC 11 to power off on its own via script from guide, then set Pi and NUC 12 to power off only when NAS sends the FSD signal. This keeps NAS, and main proxmox node alive for as much as possible.

---

# Change QDevice IP Safely in a 2-Node Proxmox Cluster (2025 Method – Corosync 3+)

If you're using a Raspberry Pi (or similar) as a QDevice in a 2-node Proxmox cluster and need to change its IP address (or reconfigure it), **do not power it off or remove it blindly**, as this may affect quorum. Use the steps below to update the QDevice cleanly and safely.

## Step-by-Step Process

### 1. **Verify quorum is currently intact**

Before proceeding, ensure your cluster is healthy:

```bash
pvecm status
```

Look for:

- `Expected votes: 3`
- `Total votes: 3` (or 2 if QDevice is offline)
- `Quorum: Yes`

### 2. **Remove the existing QDevice configuration**

You must remove the old QDevice configuration before re-adding it:

```bash
pvecm qdevice remove
```

This will disable and remove the QDevice from the cluster config.

### 3. **Change the IP address on the Raspberry Pi (QDevice)**

Log into the Pi and update its static IP. For example:

```bash
sudo nmcli con mod "Wired connection 1" ipv4.addresses 10.0.10.PI-IP/24
sudo nmcli con mod "Wired connection 1" ipv4.gateway 10.0.10.1
sudo nmcli con mod "Wired connection 1" ipv4.dns "10.0.10.PI-IP 10.0.10.CT-DNS-IP"
sudo nmcli con mod "Wired connection 1" ipv4.method manual
```

Reboot the Raspberry Pi, and SSH with the new IP.

Then verify:

```bash
ip a
cat /etc/resolv.conf
```

### 4. **Re-add the QDevice with the new IP address**

Back on either Proxmox node:

```bash
pvecm qdevice setup 10.0.10.PI-IP
```

> Make sure `sudo grep PermitRootLogin /etc/ssh/sshd_config` shows "PermitRootLogin yes"

This will:

- Set up SSH access
- Exchange certificates
- Start the `corosync-qdevice` service on all nodes

### 5. **Verify the QDevice is active and votes are correct**

Check cluster status again:

```bash
pvecm status
```

You should now see:

- `Expected votes: 3`
- `Total votes: 3`
- All nodes and the QDevice listed with `Votes: 1`
- `Flags: Quorate Qdevice`

Also check:

```bash
pvecm nodes
```

The QDevice should show `Votes: 1`.

### Done!

Your QDevice is now active on the new IP and the cluster remains quorate. No node vote adjustment was necessary, as modern Proxmox handles this automatically via QDevice.

---

# Configure Docker on a new LXC CT running Ubuntu

```bash
apt update && apt upgrade -y && apt autoremove -y
```

Then, run the following to configure Docker in an Ubuntu LXC CT:

```bash
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
```

```bash
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```

```bash
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

---

# Enabling FileBrowser Access to Unprivileged LXC Containers on Proxmox

### Docker Compose for FileBrowser on host node

```yaml
services:
    filebrowser:
        image: filebrowser/filebrowser:latest
        container_name: filebrowser
        volumes:
            - /nvme-zfs/:/srv
            - ./filebrowser.db:/database.db
            - ./settings.json:/config/settings.json
        ports:
            - "10180:80"
        restart: unless-stopped
        user: "100000:100000"
        environment:
            - PUID=100000
            - PGID=100000
```

### Confirm the CT is Unprivileged

```bash
pct config <VMID> | grep unprivileged
```

Expected output:

```
unprivileged: 1
```

If not present, the CT is privileged and **should not be modified this way.**

### Set Host Ownership and Permissions

Replace `<VMID>` with your container ID.

```bash
chown 100000:100000 /nvme-zfs/subvol-<VMID>-disk-0
chmod 755 /nvme-zfs/subvol-<VMID>-disk-0
```

This makes the CT's root filesystem accessible to FileBrowser (or any app running as UID 100000).

### Restart FileBrowser to Apply Changes

Docker containers may cache mount permissions. Restarting ensures updated access is recognized.

```bash
docker restart filebrowser
```

### ❌ Do **NOT** Do This For:

- Privileged containers (e.g., media containers with `PUID=0`)
- Shared volumes like `/mnt/nas-media` or NFS mounts
- Anything that must remain owned by `root:root`

This ensures FileBrowser has seamless access to container volumes, without breaking container-internal ownership.

---

# Reduce Swappiness on Proxmox Nodes (Recommended for High-RAM Setups)

Each NUC node in the Proxmox cluster has 32 GB of 3200 MHz DDR4 RAM. By default, Linux uses a `vm.swappiness` value of `60`, which can lead to premature swapping even when plenty of RAM is free. This is suboptimal on systems with fast memory and high available RAM.

Why lower `swappiness`?

- Keeps inactive processes in fast RAM instead of slower swap.
- Improves performance and responsiveness.
- Reduces unnecessary wear on SSDs (even fast ones like the Samsung 990 PRO).
- Ideal for homelab clusters with generous RAM and light-to-medium workloads.

## Recommended Configuration

Apply the following on **both nodes** (`pve-node-a` and `pve-node-b`):

```bash
# Lower swappiness temporarily
sysctl vm.swappiness=10

# Make it persistent across reboots
echo "vm.swappiness=10" >> /etc/sysctl.conf

# (Optional) Clear current swap to start fresh
swapoff -a && swapon -a
```

You can try this on one node first to observe any effects before applying cluster-wide.

This configuration ensures that your Proxmox nodes prioritize RAM usage over swap, making the most of your hardware’s capabilities.

---
