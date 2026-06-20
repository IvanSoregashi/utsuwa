#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Gitea (Git Service)
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
BULK_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Gitea Git Repositories..."

# Create secure state directory (mounted over NFS to Proxmox hosts)
mkdir -p "${SECURE_PATH}/app/gitea_repos"

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/app/gitea_repos"
echo "  Gitea directories initialized successfully."
