# Proxmox Cluster (homelab-cluster)

- Nodes:
    - pve-nuc12-01 (192.168.10.10)
    - pve-nuc11-01 (192.168.10.11)
    - pve-eqi13-01 (192.168.10.12)
- QDevice (Raspberry Pi): 192.168.10.51
- Total votes: 4
- Quorum: 2 required
- Config backed up: /etc/pve/corosync.conf.backup-2025-05-12

---

# Proxmox No-Subscription Popup Patch

**Reference:**
[https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/](https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/)

### Apply Patch (for 8.4.5 and up):

```bash
sed -i.backup -z "s/res === null ||\n\s* res === undefined ||\n\s* \!res ||\n\s* res.data.status.toLowerCase() \!== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service
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

> **DEPRECATED METHOD**

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

**DATACENTER > NOTIFICATIONS > NOTIFICATION MATCHERS > ADD

Give it a name, leave the filters as they are, do not touch them, then:

Targets to notify > select the target you created in `Notification Target`

---

# UPS Auto Shutdown with NUT Network Client

[UPS Integration on Proxmox](https://av1155.github.io/andreaventi-homelab/guides/21-ups-auto-shutdown.html#ups-integration-on-proxmox)

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
sudo nmcli con mod "Wired connection 1" ipv4.addresses 192.168.10.51/24
sudo nmcli con mod "Wired connection 1" ipv4.gateway 192.168.10.1
sudo nmcli con mod "Wired connection 1" ipv4.dns "192.168.10.51 192.168.10.100"
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
pvecm qdevice setup 192.168.10.51
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

Apply the following on **both nodes** (`pve-nuc12-01` and `pve-nuc11-01`):

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

# Node Maintenance (reboot / BIOS / kernel)

```bash
ha-manager crm-command node-maintenance enable <node>
ha-manager status | grep -E "lrm <node>|<node>, started"   # wait until: maintenance mode, nothing started
systemctl reboot --firmware-setup    # clean reboot directly into BIOS Setup (one-shot). Or: reboot
# after node is back:
ha-manager crm-command node-maintenance disable <node>
```

---

# BIOS Updates — NUC 11 / NUC 12

Asus hosts NUC firmware. Download the **BIOS Full Package** zip.

| Node         | Board      | BIOS ID  | Page                                                          |
| ------------ | ---------- | -------- | ------------------------------------------------------------- |
| pve-nuc11-01 | NUC11PAHi5 | PATGL357 | https://www.asus.com/uk/supportonly/nuc11pahi5/helpdesk_bios/ |
| pve-nuc12-01 | NUC12WSHi5 | WSADL357 | https://www.asus.com/supportonly/nuc12wshi5/helpdesk_bios/    |

Applied 2026-09-01: NUC 11 0043 → 0058, NUC 12 0086 → 0098.

### Flash from the node's own EFI partition (no USB stick)

```bash
# Mac: take only the F7 capsule from the zip
scp "Capsule File for BIOS Flash through F7/<ID>.<ver>.CAP" root@<node>:/boot/efi/

# Node
ha-manager crm-command node-maintenance enable <node>
systemctl reboot --firmware-setup
```

1. Setup → Boot → Boot Configuration → **Fast Boot = Disabled** → F10
2. Tap **F7** at POST → BIOS Flash Update → SATA/OS drive → the `.CAP` → confirm. Do not touch until it reboots itself.
3. `systemctl reboot --firmware-setup` → **F9** → re-apply:
    - Power → Secondary Power Settings → **After Power Failure = Power On**
    - Power → Secondary Power Settings → **HDD LED Brightness = 0**
    - Cooling → Fan Control Mode = **Cool** (NUC 11)
    - Boot → **Secure Boot = Disabled**, **Fast Boot = Disabled**
4. `rm /boot/efi/*.CAP` · `dmidecode -s bios-version` · `ha-manager crm-command node-maintenance disable <node>`

> JetKVM keyboard does not work inside the NUC 11 BIOS Setup. Use a physical USB keyboard; JetKVM as display only.
> BIOS includes newer Intel ME → no downgrade possible.

### Beelink EQi13 Pro

BIOS family is **EQI12D4xx** (same board as EQi12-D4). Look under _"EQi12 (Non-onboard memory)"_ in Beelink's BIOS Update Summary blog posts, not EQi13. Current: `EQI12D402`. Confirm with `support-pc@bee-link.com` (model, BIOS string, SN) before flashing.

---

# Notifications — mail-to-root Disabled

Only the **Google-Homelab** SMTP target delivers. The built-in `mail-to-root` sendmail target sends directly from the node IP → Gmail rejects (`550 5.7.1`). Disabled 2026-09-01:

```bash
pvesh set /cluster/notifications/endpoints/sendmail/mail-to-root --disable 1   # --disable 0 reverts
```

> Local root mail is forwarded into the notification system (`proxmox-mail-forward`). With `mail-to-root` enabled + `/etc/aliases.db` present, bounces loop and flood the inbox. Keep it disabled.

Check for bounce loops: `journalctl -u postfix --since -1h | grep -c "from=<>"` → 0.

---

# UPS / NUT

- NAS `10.0.10.50` = NUT server. Nodes = `slave` clients (each shuts down only itself; multiple clients do not conflict).
- `/etc/nut/upsmon.conf`: `MONITOR ups@10.0.10.50 1 monuser secret slave`
- Verify: `upsc ups@10.0.10.50 ups.status` → `OL`
- pve-eqi13-01 has no `nut-client` → no graceful shutdown. **TODO.**

---

# iGPU Passthrough — Current Method

CT config (replaces the deprecated `lxc.cgroup2` / `lxc.mount.entry` block):

```
dev0: /dev/dri/card0
dev1: /dev/dri/renderD128
```

### card0 vs card1

Anything with an EDID on HDMI at boot (JetKVM, monitor) → `simpledrm` takes `card0`, iGPU becomes `card1` → `Device /dev/dri/card0 does not exist`. Fixed on all nodes in `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet initcall_blacklist=simpledrm_platform_driver_init"
```

`update-grub` + reboot. Verify: `ls -la /dev/dri/by-path/` → `pci-0000:00:02.0-card -> ../card0`

> Do not install `linux-headers-amd64` on Proxmox (pulls Debian stock kernels). Use `proxmox-default-headers`.

---

# Autostart vs NFS Race (tdarr nodes)

CT 108 / 109 bind-mount `/mnt/pve/nas-ha-nfs/tdarr-cache`. `pve-guests` starts before `pvestatd` mounts the NFS storage → `startup for container failed` on every boot. Fixed on all nodes:

```bash
pvenode config set --startall-onboot-delay 20    # GUI: node → System → Options → Start on boot delay
```

Check boot start result: `grep "vzstart:<id>" /var/log/pve/tasks/index | tail -1` → `OK`
Full task log: `cat /var/log/pve/tasks/*/<UPID>`

---

# NUC 11 Instability (2026)

**Symptom:** hard freeze (power LED on, nothing logged) or found powered off. HA fails over. Power-cycle → rejoins normally.

**Crashes:** Jul 22 (during vzdump), Aug 3, Aug 21 (during replication receive). All on kernel 7.0.14. 53 clean days before it on the previous kernel.

**Findings:**

- `irq 16: nobody cared` (i2c_i801 + snd_hda_codec) on every 7.0.14 boot, absent on the stable boot
- pstore empty, journal ends abruptly → no panic recorded
- BIOS was 0043 (2022). Drives, RAM, idle temps fine
- Power brick: JUYOON 120 W (same model as NUC 12)
- CPU is **i5-1135G7**, not 1145G7

**Applied 2026-09-01:**

- BIOS 0058 (microcode 0x9A → 0xBC, ME 15.0.35 → 15.0.52)
- Kernel 7.0.14-14
- `/etc/modprobe.d/blacklist-irq16.conf`: `blacklist snd_hda_intel`, `blacklist i2c_i801` → IRQ 16 storm gone
- After Power Failure = Power On, Fan = Cool

**Rule:** no crash by **2026-10-24** → fixed. Crash before → move RAM + 990 Pro + 870 EVO into a barebones replacement.
After a crash: `journalctl --list-boots` · `journalctl -b -1 --no-pager | tail -20`

**Not done:** brick swap with NUC 12, memtest86+ (in GRUB menu), `WATCHDOG_MODULE=iTCO_wdt` in `/etc/default/pve-ha-manager`, netconsole.

---

# Post-Upgrade Cleanup

```bash
apt autoremove --purge -y && apt clean
apt purge -y $(dpkg -l | awk '/^rc/{print $2}')   # configs of removed packages
```

---

# Docker Won't Start in a CT — `fatal error: stack overflow` (bbolt)

`journalctl -u docker -b | grep -E "fatal error|panic:"` → `stack overflow` in `go.etcd.io/bbolt` = corrupted Docker metadata DB (seen on ct-security after HA restart-migration, 2026-09-01).

```bash
systemctl stop docker docker.socket
mv /var/lib/docker/network/files/local-kv.db{,.bad}      # usual culprit; if still failing, next: /var/lib/docker/volumes/metadata.db
systemctl reset-failed docker; systemctl start docker; systemctl is-active docker
```

User-defined networks are gone → containers on them exit 128 and cannot be `docker start`ed (stale network ID). Recreate:

- Local compose: `cd <dir> && docker compose up -d --force-recreate` (find dir: `docker inspect <c> --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'`)
- Portainer stacks (`/data/compose/…`): bring the agent up via local compose first, then Portainer → Stacks → Update the stack

Volume data is untouched. `rm local-kv.db.bad` once healthy.
