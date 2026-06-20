#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Nagare Backups
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
DATA_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Nagare Proxmox VM/LXC Backup targets..."

# Create data backup target directory
mkdir -p "${DATA_PATH}/nagare_backups"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}/nagare_backups"
echo "  Nagare Backups directory initialized successfully."
