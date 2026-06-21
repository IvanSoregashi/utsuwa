#!/bin/bash
# ==============================================================================
# Utsuwa: eMMC Hardening Suite - Filesystem Optimization
# Enables 'noatime' on the root filesystem to reduce disk writes.
# ==============================================================================

set -euo pipefail

echo -e "--> Optimizing Filesystem for eMMC longevity..."

# 1. Enable noatime
echo "  Setting noatime on root filesystem..."
cp /etc/fstab /etc/fstab.bak

# This sed command finds the '/' mount and adds noatime to options if not present
# It handles cases where options might be 'defaults' or others
sed -i 's/\(UUID=[^ ]* \/ [^ ]* \)\([^ ]*\)\(.*\)/\1\2,noatime\3/' /etc/fstab

# Remount root to apply changes
mount -o remount /
systemctl daemon-reload

echo -e "  Filesystem optimization complete."
