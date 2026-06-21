#!/bin/bash
# ==============================================================================
# Utsuwa: eMMC Hardening Suite - Docker Optimization
# Moves docker root to NVMe.
# ==============================================================================

set -euo pipefail

# --- Parameters ---
DATA_PATH="$1"
DOCKER_ROOT="${DATA_PATH}/docker"

echo -e "--> Relocating Docker storage to ${DOCKER_ROOT}..."

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

echo -e "  Docker storage relocated."
