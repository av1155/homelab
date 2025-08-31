# Permissions and PUID/PGID

All media containers (Radarr, Sonarr, Plex, qBittorrent, etc.) are configured with:

```yaml
PUID=0
PGID=1000
```

This ensures compatibility with the NAS media share mounted at:

```bash
/mnt/nas-media
```

The mount is owned by:

```bash
UID=0 (root)
GID=1000
```

This allows the containers to read and write to the NAS media folders (Movies, TV Shows, Downloads) without permission issues.

To confirm ownership:

```bash
ls -ldn /mnt/nas-media
```

If needed, you can adjust folder ownership on the NAS or mount point like this:

```bash
chown -R 0:1000 /mnt/nas-media
chmod -R 775 /mnt/nas-media
```

> Note: 775 allows the group (GID 1000) full read/write, while keeping permissions secure for others.

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

# NFS Mount Setup in LXC for Media Share

## 0. Create the mount directory on host

```bash
mkdir /mnt/nas-media
```

## 1. On Proxmox Host

Ensure this line is in /etc/fstab:

```bash
<NFS-TARGET-IP>:/volume1/Media /mnt/nas-media nfs defaults,_netdev,nofail,x-systemd.automount 0 0
```

Then mount it:

```bash
mount -a
```

## 2. LXC Container Config (/etc/pve/lxc/<vmid>.conf)

Use a proper bind mount:

```bash
lxc.mount.entry: /mnt/nas-media mnt/nas-media none bind,create=dir
```

## 3. Inside Container

Point Docker containers to `/mnt/nas-media`:

```yaml
volumes:
    - /mnt/nas-media:/media
```

This allows full access to `/media/Movies`, `/media/TV Shows`, etc.

---

# Plex Transcoding to RAM and NFS

To reduce SSD wear and speed up streaming performance, Plex is configured to use a **RAM-backed directory** for transcoding by default, with an **optional NFS fallback**.

## 1. RAM Disk Setup in Proxmox LXC

Create the RAM transcode directory directly inside the container using `/dev/shm` (a tmpfs-backed path already mounted by Linux):

```bash
mkdir -p /dev/shm/plex_transcode
chown 0:108 /dev/shm/plex_transcode
```

This path uses **container RAM** efficiently and avoids persistent disk I/O.

## 2. NFS Fallback Setup via Proxmox Host

The NFS share is mounted on the **Proxmox host node** through the Datacenter UI:

- Go to **Datacenter > Storage > Add > NFS**
- Set ID to `nas-ha-nfs`
- Server: `10.0.10.NAS-IP`
- Export: `/volume2/proxmox-ha-storage` (or relevant path)
- Content: `Disk image, Container` (or as needed)

To bind this into the container, add the following for the config of the LXC CT ID you want:

```bash
lxc.mount.entry: /mnt/pve/nas-ha-nfs/plex-transcode mnt/plex-nfs-transcode none bind,create=dir 0 0
```

Proxmox will bind the NFS share into the container automatically.

## 3. Docker Compose Volume Mounts (Plex Service)

In your `docker-compose.yml`:

```yaml
volumes:
    - /dev/shm/plex_transcode:/ram-transcode
    - /mnt/plex-nfs-transcode:/nfs-transcode
```

This maps both the **RAM transcode directory** and **NFS fallback** into the Plex container.

## 4. Plex Transcoder Directory Setting

In the **Plex Web UI**, set:

> **Settings > Transcoder > Transcoder temporary directory**

Set it to:

```
/ram-transcode
```

Plex will now transcode to memory, giving you minimal latency and no SSD writes.

## Optional: Fallback Strategy

If `/ram-transcode` fills up due to 4K streams, app 4K movie downloads that far exceed available RAM amount, or multiple users, you can:

1. Manually change the Plex setting to `/nfs-transcode`, or
2. Automate with a health check script that switches paths and restarts the container

> To monitor RAM usage:
>
> ```bash
> df -h /dev/shm
> ```

This setup ensures maximum performance for live streaming while maintaining a persistent fallback.

---

# qBittorrent Downloads Directory

```bash
mkdir -p /mnt/nas-media/Downloads/qBittorrent/completed
mkdir -p /mnt/nas-media/Downloads/qBittorrent/incomplete
mkdir -p /mnt/nas-media/Downloads/qBittorrent/torrents
chown -R 0:1000 /mnt/nas-media/Downloads/qBittorrent
```

In the qBittorrent Web UI → Settings → Downloads:

**Default Save Path:**
`/downloads/qBittorrent/completed`

**Keep incomplete torrents in:**
`/downloads/qBittorrent/incomplete`

**Copy .torrent files to:**
`/downloads/qBittorrent/torrents`

---

# Recyclarr Profile Sync Instructions

## 1. Create Config Files

Generate Radarr config files:

```bash
recyclarr config create \
  -t remux-web-2160p \
  -t remux-web-1080p \
  -t anime-radarr
```

Generate Sonarr config files:

```bash
recyclarr config create \
  -t web-2160p-v4 \
  -t web-1080p-v4 \
  -t anime-sonarr-v4
```

To specify a custom directory:

```bash
--output-dir ~/docker/media-server/recyclarr/config/configs/
```

## 2. Edit Config Files

In each `.yml` config file:

- Set your Radarr or Sonarr `url:`
- Set your `api_key:`
- Adjust other settings as needed (e.g. quality profiles)

## 3. Sync Profiles via Docker

Use this syntax to sync specific profiles:

### Radarr

```bash
docker exec -it recyclarr recyclarr sync radarr --instance anime-radarr
docker exec -it recyclarr recyclarr sync radarr --instance remux-web-1080p
docker exec -it recyclarr recyclarr sync radarr --instance remux-web-2160p
```

### Sonarr

```bash
docker exec -it recyclarr recyclarr sync sonarr --instance anime-sonarr-v4
docker exec -it recyclarr recyclarr sync sonarr --instance web-1080p-v4
docker exec -it recyclarr recyclarr sync sonarr --instance web-2160p-v4
```

Note: Replace `recyclarr` with your actual container name if different.

## Tip

The `--instance` value must match the `instance_name:` field inside each `.yml`, not just the filename.
