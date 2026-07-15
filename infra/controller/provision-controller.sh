#!/usr/bin/env bash
# waterline controller provisioning — replay of L0+L1 as-built (14-15 Jul 2026)
# Run as root on a fresh Ubuntu 24.04 Netcup box AFTER SCP image install with SSH key.
# Usage: provision-controller.sh <tailscale-auth-key>
set -euo pipefail
TS_KEY="${1:?Usage: provision-controller.sh <tailscale-auth-key>}"
export DEBIAN_FRONTEND=noninteractive

apt update && apt full-upgrade -y
apt install -y ufw curl git jq ripgrep fd-find tinyproxy
timedatectl set-timezone UTC

curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey="$TS_KEY" --ssh

# Proxy: config + allowlist come from the repo (deploy alongside this script)
install -m 644 "$(dirname "$0")/tinyproxy.conf" /etc/tinyproxy/tinyproxy.conf
install -m 644 "$(dirname "$0")/tinyproxy-filter" /etc/tinyproxy/filter
systemctl restart tinyproxy && systemctl enable tinyproxy

echo ">>> VERIFY TAILNET SSH FROM YOUR MAC BEFORE RUNNING THE FIREWALL BLOCK <<<"
echo "Then: ufw default deny incoming; ufw default allow outgoing; ufw allow in on tailscale0; ufw --force enable"
