#!/bin/bash
# ==============================================================================
# Utsuwa: eMMC Hardening Suite - Log Throttling
# Reduces system journal writes.
# ==============================================================================

set -euo pipefail

echo -e "--> Throttling systemd journal writes..."

cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak

# Update configuration
# Use sed to replace or append lines
sed -i '/^SystemMaxUse=/c\SystemMaxUse=100M' /etc/systemd/journald.conf
sed -i '/^MaxLevelStore=/c\MaxLevelStore=info' /etc/systemd/journald.conf

# If sed didn't replace because lines were missing, append them
if ! grep -q "SystemMaxUse=100M" /etc/systemd/journald.conf; then
    echo "SystemMaxUse=100M" >> /etc/systemd/journald.conf
fi
if ! grep -q "MaxLevelStore=info" /etc/systemd/journald.conf; then
    echo "MaxLevelStore=info" >> /etc/systemd/journald.conf
fi

systemctl restart systemd-journald
echo -e "  Journal throttling configured."
