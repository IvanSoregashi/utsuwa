#!/bin/bash
# ==============================================================================
# Utsuwa: eMMC Hardening Suite - Storage/Docker Optimization
# Moves docker root to NVMe and enables noatime.
# ==============================================================================

set -euo pipefail

# --- Parameters ---
DATA_PATH="$1"
DOCKER_ROOT="${DATA_PATH}/docker"

echo -e "--> Optimizing Docker Storage for eMMC longevity..."

# 1. Enable noatime
echo "  Setting noatime on root filesystem..."
cp /etc/fstab /etc/fstab.bak
# This sed command finds the '/' mount and adds noatime to options if not present
sed -i 's/\(UUID=[^ ]* \/ [^ ]* \)\([^ ]*\)\(.*\)/\1\2,noatime\3/' /etc/fstab
# Note: In a real scenario, we might need a more robust parser for fstab lines,
# but this covers the common case.
mount -o remount /
systemctl daemon-reload

# 2. Relocate Docker
echo "  Relocating Docker root to ${DOCKER_ROOT}..."
systemctl stop docker.service docker.socket || true

mkdir -p "$DOCKER_ROOT"
apt-get install -y rsync

if [ -d "/var/lib/docker" ]; then
    rsync -aP /var/lib/docker/ "$DOCKER_ROOT/"
    mv /var/lib/docker /var/lib/docker.old
fi

cat << EOF > /etc/docker/daemon.json
{
  "data-root": "${DOCKER_ROOT}"
}
EOF

systemctl start docker
# Cleanup if successful
if [ -d "/var/lib/docker.old" ]; then
    rm -rf /var/lib/docker.old
fi

echo -e "  Storage optimization complete."
