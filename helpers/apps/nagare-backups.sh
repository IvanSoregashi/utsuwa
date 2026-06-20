#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Nagare Backups
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
BULK_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Nagare Proxmox VM/LXC Backup targets..."

# Create bulk backup target directory
mkdir -p "${BULK_PATH}/nagare_backups"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${BULK_PATH}/nagare_backups"
echo "  Nagare Backups directory initialized successfully."
