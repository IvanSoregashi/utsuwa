# Utsuwa (Node 2) - Storage & NAS Provisioning

This repository contains the configuration files, provisioning scripts, and Docker Compose definitions for **Utsuwa**, the dedicated storage node within a dual-node homelab architecture.

The purpose of these scripts is to establish an idempotent, reproducible, and secure storage environment that remains portable across different hosting environments.

---

## 1. System Architecture Context

This node operates as part of a dual-node architecture designed around the concepts of flow (compute) and vessel (storage):

1. **Nagare (The Flow):** Node 1. A Proxmox VE compute server (Intel N100) running isolated LXC containers, development environments, and CI/CD runners. It handles active application compute.
2. **Utsuwa (The Vessel):** Node 2. A headless Debian Stable storage server (Intel N150, 12GB LPDDR5) running on a local onboard eMMC boot drive, reserving the physical NVMe slots entirely for storage pools.

### Network & Security Topology
* **Access Model:** No public ports are exposed to the internet. Remote access is bridged securely via a local Tailscale VPN gateway. Physical security is the primary risk factor.
* **Encryption Strategy:**
  * High-value personal data is stored on a ZFS mirror pool (`/vault`) inside a passphrase-encrypted dataset (`vault/secure`). This dataset must be decrypted and mounted manually via SSH after a system reboot.
  * Non-critical bulk data (media, backups, e-books) is stored unencrypted on an ext4 volume (`/bulk`) and mounts automatically at boot via `/etc/fstab`.

---

## 2. Storage Abstraction Layer

To ensure complete portability, application containers do not reference host-specific storage pools directly. Instead, the system implements a standardized, system-level abstraction layer via `/etc/fstab` bind mounts:

| Host Storage Pool | Standardized Path | Purpose / Contents |
| :--- | :--- | :--- |
| `/vault/secure` (ZFS Encrypted) | `/srv/encrypted/` | High-value directories: `/vault` (Obsidian notebook), `/apps` (Docker configs) |
| `/bulk` (ext4 Unencrypted) | `/srv/data/` | Bulk directories: `/gallery` (Photos/Immich), `/books` (E-books) |

By writing all Docker Compose files to reference `/srv/encrypted/` or `/srv/data/`, the entire container stack can be cloned and run on a standard single-disk Virtual Private Server (VPS) or fallback hardware without modifying host paths.

---

## 3. Sharing & Permissions

* **Permission Alignment:** To prevent file permission conflicts between SMB, NFS, and Docker containers, a single primary non-root system user (`sendo`, UID 1000 / GID 1000) is designated as the unified owner of all data written to these pools.
* **Samba (SMB):** Runs inside a portable Docker container (`dperson/samba`) rather than on the host. It maps the abstracted paths (`/srv/encrypted/vault` and `/srv/data/gallery`) to shares, enforcing read/write permissions for the primary user via custom configuration parameters.

---

## 4. Provisioning Scripts (`setup-utsuwa.sh`)

The core automation script in this repository handles the initial setup and maintenance of Utsuwa's directories, permission alignments, and Samba configuration.

### Key Logic Features:
1. **Smart Mount Verification:** To prevent containers from writing directly to the eMMC boot drive if storage pools are unmounted (which would exhaust disk space and risk OS instability), the script checks system mount states.
   * If a target path is defined in `/etc/fstab` or detected via ZFS but is currently unmounted, the script safely halts execution.
   * If run on a standard single-disk VPS (where these mount points do not exist in `/etc/fstab`), it bypasses the ZFS/fstab check and safely proceeds with normal setup.
2. **Dynamic Permissions:** Rather than hardcoding the system user, the script uses environment lookups (such as `SUDO_USER`) to dynamically resolve and apply directory ownership to the primary administrator user (UID 1000).

---

## 5. Repository Structure

```text
├── README.md               # System context and architectural documentation
├── setup-utsuwa.sh         # Idempotent provisioning & mount verification script
└── docker/
    └── samba/              # Portable SMB configuration and compose files
```
