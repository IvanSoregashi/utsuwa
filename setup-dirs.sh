#!/bin/bash
set -e

# --- 1. Argument Validation ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <path_to_secure_volume> <path_to_unencrypted_volume>"
    echo "Example: $0 /vault/secure /bulk"
    exit 1
fi

# Check if the raw directories even exist on the system
if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    echo "Error: One or both of the provided directory paths do not exist on the filesystem."
    echo "Please ensure the paths are correct."
    exit 1
fi

SECURE_PATH=$(realpath "$1")
BULK_PATH=$(realpath "$2")

echo "=================================================="
echo "Initializing Utsuwa Directory Tree"
echo "Secure Path: $SECURE_PATH"
echo "Bulk Path:   $BULK_PATH"
echo "=================================================="

# Define the user to own all directories (UID/GID 1000)
# 1. Try to find the user who typed sudo
# 2. Fall back to the user with UID 1000 (standard primary user)
# 3. Fall back to the active user ($USER)
SYS_USER=${SUDO_USER:-$(id -un 1000 2>/dev/null || echo "$USER")}


# --- 2. Smart, Universal Mount Verification ---
check_mount_safety() {
    local target_path="$1"
    local path_type="$2"

    # A. If it is currently mounted (via standard mount or ZFS), it is 100% safe.
    if mountpoint -q "$target_path" || (command -v zfs &>/dev/null && zfs mount | grep -F -q "$target_path"); then
        echo "  $path_type path ($target_path) is actively mounted. Safe."
        return 0
    fi

    # B. If not mounted, check if the system expects it to be a mount point.
    # Check /etc/fstab
    if grep -F -q "$target_path" /etc/fstab; then
        echo "CRITICAL ERROR: $path_type path ($target_path) is defined in /etc/fstab but is NOT mounted!"
        echo "Running this script now would write files directly to your system drive."
        exit 1
    fi

    # Check ZFS datasets (if ZFS is installed)
    if command -v zfs &>/dev/null && zfs list -H -o mountpoint | grep -x -q "$target_path"; then
        echo "CRITICAL ERROR: $path_type path ($target_path) is an unmounted ZFS dataset!"
        echo "Please unlock and mount your ZFS pool first."
        exit 1
    fi

    # C. If not mounted and not expected to be a mount (e.g., on a VPS),
    # check if the directory is writeable.
    if [ -w "$target_path" ]; then
        echo "  $path_type path ($target_path) is a standard writeable directory. Safe."
        return 0
    else
        echo "ERROR: $path_type path ($target_path) is not writeable by this script."
        exit 1
    fi
}

echo "--> Verifying drive mount safety..."
check_mount_safety "$SECURE_PATH" "Secure"
check_mount_safety "$BULK_PATH" "Bulk"


# --- 2. Create Directory Structures ---

echo "--> Creating encrypted volume directories..."
# Secure Application Configurations (State)
mkdir -p "${SECURE_PATH}/app/syncthing"
mkdir -p "${SECURE_PATH}/app/immich_db"
mkdir -p "${SECURE_PATH}/app/webdav"

mkdir -p "${SECURE_PATH}/app/observability"
mkdir -p "${SECURE_PATH}/app/net_library"

# Git repository state (to be mounted over NFS to Nagare)
mkdir -p "${SECURE_PATH}/app/gitea_repos"

# Your physical Obsidian notebook vault
mkdir -p "${SECURE_PATH}/vault"

echo "--> Creating unencrypted bulk volume directories..."
# Bulk dynamic data and system caches
mkdir -p "${BULK_PATH}/gallery"              # Formerly gazo
mkdir -p "${BULK_PATH}/immich_system"        # Transcodes, thumbnails, ML caches
mkdir -p "${BULK_PATH}/net_library_books"    # Raw ePUB storage
mkdir -p "${BULK_PATH}/nagare_backups"       # Target for Nagare's Proxmox VM/LXC backups

mkdir -p "${SECURE_PATH}/app/samba"

# --- 3. Generate Portable smb.conf ---
SMB_CONF_PATH="${SECURE_PATH}/app/samba/smb.conf"
if [ ! -f "$SMB_CONF_PATH" ]; then
    echo "--> Generating portable smb.conf for $SYS_USER..."
    # NOTE: We use EOF (unquoted) so Bash replaces $SYS_USER with the real username!
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
    sudo chown ${SYS_USER}:${SYS_USER} "$SMB_CONF_PATH"
    echo "  smb.conf successfully generated at $SMB_CONF_PATH"
else
    echo "  smb.conf already exists. Skipping generation."
fi



# --- 3. Align Permissions to sendo ---
echo "--> Aligning file permissions..."
sudo chown -R ${SYS_USER}:${SYS_USER} "$SECURE_PATH"
sudo chown -R ${SYS_USER}:${SYS_USER} "$BULK_PATH"

# --- 4. Setup Standardized /srv Mounts ---
echo "--> Preparing standardized /srv bind mounts..."
sudo mkdir -p /srv/encrypted
sudo mkdir -p /srv/storage

# Helper function to append to /etc/fstab safely if the mount point isn't already mapped
add_fstab_entry() {
    local src="$1"
    local dst="$2"
    if ! grep -qs "$dst" /etc/fstab; then
        echo "Appending fstab bind mount for $dst..."
        echo "$src    $dst    none    bind,nofail    0    0" | sudo tee -a /etc/fstab > /dev/null
    else
        echo "fstab entry for $dst already exists. Skipping."
    fi
}

add_fstab_entry "$SECURE_PATH" "/srv/encrypted"
add_fstab_entry "$BULK_PATH" "/srv/storage"

# --- 5. Mount the new paths (Idempotent check) ---
echo "--> Mounting standardized /srv layers..."

if ! mountpoint -q /srv/encrypted; then
    sudo mount /srv/encrypted || echo "Warning: /srv/encrypted could not mount automatically (is the pool locked?)"
else
    echo "  /srv/encrypted is already mounted. Skipping."
fi

if ! mountpoint -q /srv/storage; then
    sudo mount /srv/storage || echo "Warning: /srv/storage could not mount."
else
    echo "  /srv/storage is already mounted. Skipping."
fi

echo "=================================================="
echo "Initialization Complete!"
echo "Standardized system-level mappings:"
echo "  /srv/encrypted  -> $SECURE_PATH"
echo "  /srv/storage    -> $BULK_PATH"
echo "=================================================="
