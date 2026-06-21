#!/bin/bash
# ==============================================================================
# Utsuwa: Docker Engine Installer for Debian
# Sets up official Docker repositories and installs Docker Engine.
# ==============================================================================

set -euo pipefail

# --- Parameters ---
# Use the user who invoked sudo, fallback to the current user
SYS_USER="${1:-${SUDO_USER:-$USER}}"

echo -e "--> Checking Docker installation..."

if command -v docker &>/dev/null; then
    echo "  Docker is already installed. Skipping."
    exit 0
fi

echo "  Installing Docker Engine dependencies..."
apt-get update
apt-get install -y ca-certificates curl

echo "  Configuring Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources using modern DEB822 format
cat <<EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "  Installing Docker Engine and plugins..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "  Adding user '${SYS_USER}' to docker group..."
if getent group docker >/dev/null; then
    usermod -aG docker "$SYS_USER"
    echo -e "  ✔ User '${SYS_USER}' added to 'docker' group. Please log out and back in for changes to take effect."
else
    echo -e "  ! Warning: Docker group not found. Docker might not be installed correctly."
fi

echo -e "  ✔ Docker installed successfully."
