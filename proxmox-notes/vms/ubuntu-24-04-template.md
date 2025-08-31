# Ubuntu 24.04 Template Setup

## 1. Verify Networking

```bash
ip a
```

## 2. Check Guest Agent Status

```bash
systemctl status qemu-guest-agent
```

## 3. Update System

```bash
sudo apt update && sudo apt upgrade -y
```

## 4. Install QEMU Guest Agent

```bash
sudo apt install -y qemu-guest-agent
```

## 5. Reboot

```bash
sudo reboot
```
