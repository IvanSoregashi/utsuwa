#!/bin/bash
# ==============================================================================
# Utsuwa: eMMC Hardening Suite - Memory/Swap Optimization
# Configures ZRAM and NVMe fallback swap.
# ==============================================================================

set -euo pipefail

# --- Parameters ---
DATA_PATH="$1"
SWAP_FILE="${DATA_PATH}/swapfile"

echo -e "--> Setting up Memory/Swap Optimizations..."

# 1. ZRAM Configuration
echo "  Installing and configuring ZRAM..."
apt-get update && apt-get install -y zram-tools

cat << EOF > /etc/default/zramswap
ALGO=zstd
SIZE=3072
PRIORITY=100
EOF

systemctl enable --now zramswap
systemctl restart zramswap

# 2. NVMe Swap File
if [ ! -f "$SWAP_FILE" ]; then
    echo "  Creating 4GB NVMe fallback swap file..."
    fallocate -l 4G "$SWAP_FILE"
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
fi

# Ensure fstab entry for swap
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "  Adding swap to fstab..."
    echo "${SWAP_FILE}   none   swap   defaults,pri=1   0   0" >> /etc/fstab
fi

swapon -a

# 3. Minimize swappiness
echo "  Setting vm.swappiness to 10..."
sysctl -w vm.swappiness=10
if ! grep -q "vm.swappiness" /etc/sysctl.d/99-sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.d/99-sysctl.conf
else
    sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.d/99-sysctl.conf
fi
sysctl -p /etc/sysctl.d/99-sysctl.conf

echo -e "  Memory optimization complete."
