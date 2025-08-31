# Guide: Mounting Synology NAS NFS Share into Proxmox LXC (Vaultwarden Backups)

This guide documents how to mount a Synology **NFS share** into a **Proxmox LXC container** for use with Vaultwarden backups, and configure the backup container (`ttionya/vaultwarden-backup`).  
Covers both **unprivileged** and **privileged** LXC scenarios.

---

## 1. Configure NFS on Synology NAS

1. Open **Control Panel → Shared Folder** → select your folder (e.g. `vaultwarden-backups`).
2. Click **Edit → Permissions** and grant your intended NAS user **Read/Write**.
    - Example: user `jeffadminuser` = **Read/Write**.
3. Go to the **NFS Permissions** tab and add a rule:
    - **Hostname/IP:** `10.10.10.0/24` (your LAN subnet)
    - **Privilege:** `Read/Write`
    - **Squash:** `No mapping` (equivalent to `no_root_squash`)
    - **Security:** `sys`
    - ✅ Enable asynchronous

Save and apply.

---

## 2. Mount NFS Share on Proxmox Host

> Do the following on all hosts (nodes) if you have a HA cluster.

On Proxmox host (`pve-node-a`), edit `/etc/fstab`:

```fstab
<NFS-TARGET-IP>:/volume1/vaultwarden-backups /mnt/vaultwarden-backups nfs defaults,_netdev,nofail,x-systemd.automount 0 0
```

Reload mounts:

```bash
mkdir -p /mnt/vaultwarden-backups
mount -a
```

Check:

```bash
ls -ld /mnt/vaultwarden-backups
```

---

## 3. Bind-Mount into LXC Container

Edit the CT config on Proxmox host:

```bash
nano /etc/pve/lxc/<LXC-ID>.conf
```

Add:

```conf
lxc.mount.entry: /mnt/vaultwarden-backups mnt/vaultwarden-backups none bind,create=dir
```

Restart container:

```bash
pct restart <LXC-ID>
```

Inside the CT (`ct-security`):

```bash
ls -ld /mnt/vaultwarden-backups
```

---

## 4. Permissions Behavior

### If CT is **unprivileged** (`unprivileged: 1`):

- CT root (`uid=0`) maps to **host UID 100000**.
- Files written **inside the CT** appear as `100000:100000` on the host.
- Files written by **host root** appear as `nobody:nogroup` inside CT.
- This is expected — backups still work.

### If CT is **privileged** (`unprivileged: 0`):

- CT root maps directly to **host root** (`uid=0`).
- File ownership is consistent (`root:root`) both inside and outside the CT.
- Less secure (container processes run as real root on host).

---

## 5. Verifying Access

Inside the CT:

```bash
# Create test file
echo "test" > /mnt/vaultwarden-backups/test.txt
ls -l /mnt/vaultwarden-backups
```

On Proxmox host:

```bash
ls -ln /mnt/vaultwarden-backups
```

Expected results:

- If **unprivileged CT** → shows as `100000:100000` on host.
- If **privileged CT** → shows as `0:0` (root) on host.

Both are valid — backups work either way.

---

## 6. Configure rclone for Backup Container

The backup container uses **rclone** for storage backends. Since we are writing to the NAS via bind mount, configure a **local remote**:

```bash
mkdir -p /root/docker/security-stack/vaultwarden/rclone-config

docker run --rm -it \
  -v /root/docker/security-stack/vaultwarden/rclone-config:/config \
  ttionya/vaultwarden-backup:latest rclone config
```

Steps inside wizard:

1. `n` → new remote
2. Name: `BitwardenBackup`
3. Storage: `33` (local disk)
4. Accept defaults → `y` to save

Verify:

```bash
docker run --rm -it \
  -v /root/docker/security-stack/vaultwarden/rclone-config:/config \
  ttionya/vaultwarden-backup:latest rclone config show
```

Should show:

```ini
[BitwardenBackup]
type = local
```

---

## 7. Docker Compose Example for Vaultwarden + Backup

```yaml
services:
    vaultwarden:
        image: vaultwarden/server:latest
        container_name: vaultwarden
        restart: always
        ports:
            - "5151:80"
        volumes:
            - /root/docker/security-stack/vaultwarden/data:/data
        environment:
            - DOMAIN=${DOMAIN}
            - SIGNUPS_ALLOWED=${SIGNUPS_ALLOWED}
            - ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}
            - UID=0
            - GID=0

    vaultwarden-backup:
        image: ttionya/vaultwarden-backup:latest
        container_name: vaultwarden-backup
        restart: always
        depends_on:
            - vaultwarden
        volumes:
            - /root/docker/security-stack/vaultwarden/data:/bitwarden/data:ro
            - /root/docker/security-stack/vaultwarden/rclone-config:/config
            - /mnt/vaultwarden-backups:/backup # NAS NFS bind mount
            - /etc/localtime:/etc/localtime:ro
            - /etc/timezone:/etc/timezone:ro
        environment:
            - TIMEZONE=America/New_York

            # Scheduling & retention
            - CRON=0 * * * *
            - BACKUP_KEEP_DAYS=30

            # Archive & encryption
            - ZIP_ENABLE=TRUE
            - ZIP_TYPE=7z
            - ZIP_PASSWORD=${VW_BACKUP_PASSWORD}

            # rclone destination
            - RCLONE_REMOTE_NAME=BitwardenBackup
            - RCLONE_REMOTE_DIR=/backup

            # Notifications - SMTP
            - MAIL_SMTP_ENABLE=TRUE
            - MAIL_TO=${VW_BACKUP_EMAIL_RECIPIENT} # recipient(s)
            - MAIL_WHEN_SUCCESS=TRUE # disable success emails
            - MAIL_WHEN_FAILURE=TRUE # enable only on failures
            - MAIL_SMTP_VARIABLES=-S smtp-use-starttls -S smtp=smtp://smtp.gmail.com:587 -S smtp-auth=login -S smtp-auth-user=${SMTP_EMAIL} -S smtp-auth-password=${SMTP_PASSWORD} -S from=${SMTP_EMAIL}

            # Optional display name
            - DISPLAY_NAME=vaultwarden

    # vaultwarden-backup:
    #     image: bruceforce/vaultwarden-backup:latest
    #     container_name: vaultwarden-backup
    #     restart: always
    #     depends_on:
    #         - vaultwarden
    #     volumes:
    #         - /root/docker/security-stack/vaultwarden/data:/data:ro
    #         - /root/docker/security-stack/vaultwarden/backup:/backup
    #         - /etc/localtime:/etc/localtime:ro
    #         - /etc/timezone:/etc/timezone:ro
    #     environment:
    #         - CRON_TIME=0 * * * * # every hour
    #         - DELETE_AFTER=30 # keep backups for 30 days
    #         - BACKUP_DIR=/backup
    #         - TIMESTAMP=true
    #         - ENCRYPTION_PASSWORD=${VW_BACKUP_PASSWORD}
    #         - UID=0
    #         - GID=0
```

---

## 8. Testing Backups

Bring container up:

```bash
docker compose up -d vaultwarden-backup
```

Force backup run:

```bash
docker exec -it vaultwarden-backup backup
```

Check NAS path:

```bash
ls -lh /mnt/vaultwarden-backups
```

---

## 9. Security Notes

- **Unprivileged LXC** is safer → prefer unless you need identical UID/GID mapping.
- Synology’s `No mapping` (no_root_squash) lets CT root write files without restriction.
- Always enable **ZIP_PASSWORD** for encryption before pushing to NAS/cloud.
- Verify restores regularly using the [restore-instructions.txt](restore-instructions.txt).

---

## 10. Restoring from Backup

> ⚠️ **Warning:** Restoring will overwrite your current Vaultwarden data.  
> Always test restores on a separate environment before doing it in production.

### Steps

1. **Stop Vaultwarden container**

    ```bash
    docker stop vaultwarden
    ```

2. **Locate your backup file**  
   Backups are stored in `/mnt/vaultwarden-backups`.  
   Example file:

    ```
    vaultwarden-backup-20250830.7z
    ```

3. **Run restore command**  
   From inside your project directory:

    ```bash
    docker run --rm -it \
      -v /root/docker/security-stack/vaultwarden/data:/bitwarden/data \
      -v /mnt/vaultwarden-backups:/bitwarden/restore \
      -v /root/docker/security-stack/vaultwarden/rclone-config:/config \
      -e DATA_DIR="/bitwarden/data" \
      ttionya/vaultwarden-backup:latest restore \
      --zip-file /bitwarden/restore/vaultwarden-backup-20250830.7z \
      --password ${VW_BACKUP_PASSWORD} \
      --force-restore
    ```

    - `--zip-file` → path to the encrypted backup archive inside container
    - `--password` → your `${VW_BACKUP_PASSWORD}`
    - `--force-restore` → skips confirmation prompt

4. **Start Vaultwarden again**
    ```bash
    docker start vaultwarden
    ```

---

### Notes

- You can restore individual files (`--db-file`, `--config-file`, `--attachments-file`, etc.) if needed.
- Test restores periodically to confirm backup integrity.
