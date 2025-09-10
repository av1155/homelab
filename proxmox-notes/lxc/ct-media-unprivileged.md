# Unprivileged LXC for Media Server

<!--toc:start-->

- [Unprivileged LXC for Media Server](#unprivileged-lxc-for-media-server)
    - [Prepare the LXC Environment](#prepare-the-lxc-environment)
    - [Create the NAS Shared Folder for NFS](#create-the-nas-shared-folder-for-nfs)
    - [Configure NFS Permissions on the NAS](#configure-nfs-permissions-on-the-nas)
    - [Mount the NFS Folder](#mount-the-nfs-folder)
    - [Enable Intel iGPU passthrough for VAAPI/QSV in LXC on Proxmox](#enable-intel-igpu-passthrough-for-vaapiqsv-in-lxc-on-proxmox)
    - [Pass Intel iGPU and TUN device into the LXC](#pass-intel-igpu-and-tun-device-into-the-lxc)
        - [GPU (Intel iGPU)](#gpu-intel-igpu)
        - [VPN (qBittorrent via Gluetun)](#vpn-qbittorrent-via-gluetun)
    - [Docker Container Environment (inside CT)](#docker-container-environment-inside-ct)
    - [Plex RAM & Downloads Transcode Directories (inside CT)](#plex-ram-downloads-transcode-directories-inside-ct)
        - [NFS Mount for Plex Downloads Transcode](#nfs-mount-for-plex-downloads-transcode)
    - [Ownership / PUID-PGID policy](#ownership-puid-pgid-policy)
    - [Example Container Config (`/etc/pve/lxc/<vmid>.conf`)](#example-container-config-etcpvelxcvmidconf)

<!--toc:end-->

---

## Prepare the LXC Environment

Update and upgrade:

```bash
apt update -y && apt upgrade -y
reboot
```

Install Docker using the apt repository:

> Run the following command to uninstall all conflicting packages:
>
> ```bash
> for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
> ```

1. Set up Docker's apt repository.

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

2. Install the Docker packages.

    ```bash
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ```

---

## Create the NAS Shared Folder for NFS

On a Synology NAS:

`Control Panel > Shared Folder > Create > Create Shared Folder`:

- Do **not** enable encryption
- Do **not** enable data checksum for advanced data integrity
- Do **not** enable file compression
- Leave permissions at the default (no need to tick any boxes)

> Permissions don’t matter here, since we use **NFS squash = map all users to admin** in the next step.  
> This forces all clients (Proxmox + containers) to access the share as `admin`, avoiding UID/GID mismatch issues.
> Only adjust Synology permissions here if you want to **explicitly deny access** to certain users or groups.

---

## Configure NFS Permissions on the NAS

`Control Panel > Shared Folder > media-folder > Edit`:

`NFS Permissions > Create`:

- Hostname or IP: `<YOUR-HOMELAB-SUBNET>.0/24`
- Privilege: Read/Write
- Squash: Map all users to admin
- Security: sys
- [x] Enable asynchronous

> This avoids UID/GID mismatch headaches and makes the share portable.

---

## Mount the NFS Folder

1. On the Proxmox host

    Make the mountpoint:

    ```bash
    mkdir -p /mnt/nas-media
    ```

    Add to `/etc/fstab`:

    ```bash
    <YOUR-NAS-IP>:/volume1/media-test /mnt/nas-media nfs defaults,_netdev,nofail,x-systemd.automount 0 0
    ```

    > If you have NFS 4.1 enabled in settings, then use the following instead:
    >
    > ```bash
    > <YOUR-NAS-IP>:/volume1/media-test /mnt/nas-media nfs vers=4.1,_netdev,nofail,x-systemd.automount 0 0
    > ```

    Mount immediately (without reboot):

    ```bash
    mount -a
    ```

    Check:

    ```bash
    df -h | grep nas-media
    ls -ld /mnt/nas-media
    ```

2. Pass it into your unprivileged CT

    Edit `/etc/pve/lxc/<vmid>.conf`:

    ```txt
    lxc.mount.entry: /mnt/nas-media mnt/nas-media none bind,create=dir
    ```

    Inside the CT you’ll now see it as `/mnt/nas-media`.

---

## Enable Intel iGPU passthrough for VAAPI/QSV in LXC on Proxmox

1. On the Proxmox Host (not inside CT)

    Install Intel GPU drivers and tools:

    ```bash
    apt update
    sed -i -E '/^deb /s/\bmain contrib\b/& non-free non-free-firmware/' /etc/apt/sources.list

    apt update
    apt install -y \
        intel-media-va-driver-non-free \
        intel-gpu-tools \
        intel-microcode \
        libdrm-intel1 \
        linux-headers-amd64 \
        vainfo
    ```

2. Reboot the node

    ```bash
    reboot
    ```

3. After reboot, confirm iGPU is present:

    ```bash
    lspci | grep VGA
    ```

4. Check DRM device nodes:

    ```bash
    ls -l /dev/dri
    ```

    Should show `card0` and `renderD128`.

5. Validate hardware codecs:

    ```bash
    vainfo
    ```

## Pass Intel iGPU and TUN device into the LXC

### GPU (Intel iGPU)

**Option 1: Proxmox ≥8.2 (WebUI)**

1. CT → **Resources → Add → Device Passthrough**
2. Add separately:
    - `/dev/dri/card0`
    - `/dev/dri/renderD128`

**Option 2: Manual edit (/etc/pve/lxc/<vmid>.conf)**

```txt
dev0: /dev/dri/card0
dev1: /dev/dri/renderD128
```

**Inside the CT, verify:**

```bash
ls -l /dev/dri
```

You should see `card0` and `renderD128`

```bash
apt update && apt install -y vainfo intel-media-va-driver-non-free i965-va-driver-shaders
vainfo
```

`vainfo` should list Intel hardware codecs.

---

### VPN (qBittorrent via Gluetun)

To use a VPN container, also pass `/dev/net/tun` into the CT:

**Option 1: WebUI**

- CT → **Resources → Add → Device Passthrough** → `/dev/net/tun`

**Option 2: Manual edit (/etc/pve/lxc/<vmid>.conf)**

```txt
dev2: /dev/net/tun
```

---

## Docker Container Environment (inside CT)

At this point, Docker can see both `/mnt/nas-media` and the GPU/TUN devices.  
Sample docker-compose snippet for Plex:

```yaml
services:
    plex:
        image: ghcr.io/linuxserver/plex:latest
        network_mode: host
        devices:
            - /dev/dri:/dev/dri
        environment:
            - TZ=America/New_York
            - PUID=0
            - PGID=0
        volumes:
            - /mnt/nas-media:/media
            - /root/docker/plex:/config
```

---

## Plex RAM & Downloads Transcode Directories (inside CT)

Create a RAM-backed directory for live transcode sessions, and a separate NFS-backed directory for download transcodes:

```bash
# RAM for live streaming transcodes
mkdir -p /dev/shm/plex_transcode
chown 0:0 /dev/shm/plex_transcode
chmod 1777 /dev/shm/plex_transcode
```

In the **docker-compose** file for Plex maps both:

```yaml
volumes:
    - /dev/shm/plex_transcode:/ram-transcode
    - /mnt/plex-nfs-transcode:/nfs-transcode
```

Set in Plex Web UI:

- **Settings → Transcoder → Transcoder temporary directory** → `/ram-transcode`
- **Settings → Transcoder → Downloads temporary directory** → `/nfs-transcode`

This ensures:

- **RAM (`/ram-transcode`)** is used for fast, temporary transcodes during streaming.
- **NFS (`/nfs-transcode`)** is used for transcoded downloads until clients fetch them, keeping large files off RAM.

---

### NFS Mount for Plex Downloads Transcode

1. **On the NAS (Synology):**  
   Create a shared folder (e.g. `plex-transcode`) under `/volume2/proxmox-ha-storage`.

    Set NFS permissions:
    - Host/IP: `<YOUR-HOMELAB-SUBNET>.0/24`
    - Privilege: **Read/Write**
    - Squash: **Map all users to admin**
    - Security: **sys**
    - [x] Enable asynchronous
    - [x] Allow connections from non-privileged ports (>1024)
    - [x] Allow users to access mounted subfolders

    These options are required when mounting subfolders (e.g. `/plex-transcode`) inside an unprivileged CT.

---

2. **On Proxmox Datacenter UI:**
    - Add storage: **Datacenter → Storage → Add → NFS**
    - Server: `192.168.x.x` (NAS IP)
    - Export: `/volume2/proxmox-ha-storage`
    - Content: **Disk image, Container** (or leave as needed)

---

3. **On Proxmox host / LXC config:**  
   Bind the subdir into your CT:

    ```txt
    lxc.mount.entry: /mnt/pve/nas-ha-nfs/plex-transcode mnt/plex-nfs-transcode none bind,create=dir
    ```

    Now inside the CT, the directory is available at `/mnt/plex-nfs-transcode`.

---

## Ownership / PUID-PGID policy

- **Run all containers as `PUID=0` and `PGID=0`** in compose.
- Local config paths (e.g. `/root/docker/...`) should be owned by `root:root`:
    ```bash
    chown -R 0:0 /root/docker
    ```
- The **NFS share** on Synology uses **Squash: map all users to admin**, so files appear
  as `root:root` on the CT and are writable from containers without UID/GID juggling.
- This is safe here because you’re in an **unprivileged LXC** (root inside CT is
  mapped and contained on the host).

---

## Example Container Config (`/etc/pve/lxc/<vmid>.conf`)

```txt
arch: amd64
cores: 8
dev0: /dev/dri/card0
dev1: /dev/dri/renderD128
dev2: /dev/net/tun
features: nesting=1
hostname: ct-media
memory: 8192
net0: ...
onboot: 1
ostype: ubuntu
rootfs: ...
swap: 2048
unprivileged: 1
lxc.mount.entry: /mnt/nas-media mnt/nas-media none bind,create=dir
lxc.mount.entry: /mnt/pve/nas-ha-nfs/plex-transcode mnt/plex-nfs-transcode none bind,create=dir
lxc.mount.entry: /mnt/pve/nas-ha-nfs/tdarr-cache mnt/tdarr-cache none bind,create=dir
```

---
