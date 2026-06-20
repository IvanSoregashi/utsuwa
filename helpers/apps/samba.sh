#!/bin/bash
# ==============================================================================
# Utsuwa App Setup: Samba
# ==============================================================================
set -euo pipefail

SECURE_PATH="$1"
BULK_PATH="$2"
SYS_USER="$3"

echo "--> Initializing Samba Server configuration & shares..."

# Create secure configuration directory
mkdir -p "${SECURE_PATH}/app/samba"

# Create bulk shared folders
mkdir -p "${BULK_PATH}/gallery"

# Generate portable smb.conf if it does not exist
SMB_CONF_PATH="${SECURE_PATH}/app/samba/smb.conf"
if [ ! -f "$SMB_CONF_PATH" ]; then
    echo "  Generating portable smb.conf for $SYS_USER..."
    cat << EOF > "$SMB_CONF_PATH"
[global]
    workgroup = WORKGROUP
    server string = Utsuwa NAS
    security = user
    map to guest = Bad User
    log file = /var/log/samba/%m.log
    max log size = 50
    dns proxy = no

[vault]
    comment = Personal Vault
    path = /share/vault
    browseable = yes
    writable = yes
    guest ok = no
    valid users = $SYS_USER
    force user = $SYS_USER
    force group = $SYS_USER
    create mask = 0660
    directory mask = 0770

[gallery]
    comment = Gallery
    path = /share/gallery
    browseable = yes
    writable = yes
    guest ok = no
    valid users = $SYS_USER
    force user = $SYS_USER
    force group = $SYS_USER
    create mask = 0660
    directory mask = 0770
EOF
    chown ${SYS_USER}:${SYS_USER} "$SMB_CONF_PATH"
    echo "  smb.conf successfully generated at $SMB_CONF_PATH"
else
    echo "  smb.conf already exists. Skipping generation."
fi

# Align permissions
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}/app/samba"
chown -R "${SYS_USER}:${SYS_USER}" "${BULK_PATH}/gallery"
echo "  Samba initialized successfully."
