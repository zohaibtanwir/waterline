#!/usr/bin/env bash
# waterline runner provisioning — replay of L1 as-built (14-15 Jul 2026)
# Run as root on a fresh Ubuntu 24.04 Netcup box AFTER SCP image install with SSH key.
# Usage: provision-runner.sh <tailscale-auth-key> <controller-tailnet-ip>
set -euo pipefail
TS_KEY="${1:?Usage: provision-runner.sh <ts-auth-key> <controller-ip>}"
CTRL="${2:?Usage: provision-runner.sh <ts-auth-key> <controller-ip>}"
export DEBIAN_FRONTEND=noninteractive

apt update && apt full-upgrade -y
apt install -y ufw curl git jq ripgrep fd-find
timedatectl set-timezone UTC

curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey="$TS_KEY" --ssh

curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

docker network create --driver bridge --subnet 172.30.0.0/24 sandbox-net || true
iptables -I DOCKER-USER -s 172.30.0.0/24 -d "$CTRL" -j ACCEPT
iptables -I DOCKER-USER -s 172.30.0.0/24 -d 172.30.0.0/24 -j ACCEPT
iptables -A DOCKER-USER -s 172.30.0.0/24 -j REJECT --reject-with icmp-port-unreachable
apt install -y iptables-persistent && netfilter-persistent save

mkdir -p /opt/waterline/{sandboxes,tasks,results,images/sandbox-base}
# Deploy from repo: bin/sandbox-run.sh -> /opt/waterline/, images/sandbox-base/* -> images/sandbox-base/
# Then: docker build --build-arg CLAUDE_CODE_VERSION=<pin> -t waterline/sandbox-base:v0 /opt/waterline/images/sandbox-base
# Manual per-runner: /opt/waterline/task.env (0600, model key), /root/.git-credentials (0600, PAT), GIT_TERMINAL_PROMPT=0

echo ">>> VERIFY TAILNET SSH FROM YOUR MAC BEFORE THE FIREWALL BLOCK <<<"
echo "Then: ufw default deny incoming; ufw default allow outgoing; ufw allow in on tailscale0; ufw --force enable"
