#!/bin/bash
# One-shot VPS bootstrap. Idempotent.
#
# Usage:  scp scripts/bootstrap.sh root@<host>:/tmp/
#         ssh root@<host> 'bash /tmp/bootstrap.sh'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# --- base system: full patch + automatic security updates ---
apt-get update
apt-get -y -o Dpkg::Options::=--force-confold dist-upgrade
apt-get install -y unattended-upgrades ufw curl ca-certificates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# --- swap (1 GB VPS hits OOM without it) ---
if [ ! -f /swapfile ]; then
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

# --- docker ---
# userland-proxy:false = pure iptables DNAT, no docker-proxy process per port.
if ! command -v docker >/dev/null; then
	curl -fsSL https://get.docker.com | sh
fi
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "userland-proxy": false
}
EOF
systemctl restart docker

# --- kernel tuning (UDP for pion + QUIC) ---
cat > /etc/sysctl.d/99-vibes.conf <<'EOF'
net.core.rmem_max = 7340032
net.core.wmem_max = 7340032
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.netdev_max_backlog = 5000
vm.swappiness = 10
EOF
sysctl --system

# --- non-root deploy user ---
id deploy >/dev/null 2>&1 || useradd -m -s /bin/bash -G docker deploy

# --- UFW: SSH only ---
# App ports are docker-published; userland-proxy:false makes docker's DNAT bypass
# ufw, so per-app rules here are inert (re-enable the proxy → add them back).
ufw allow 22/tcp
ufw --force enable

# --- SSH hardening ---
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload ssh

# --- vibes network + base dir ---
# CI workflows mkdir each /opt/vibes/<app> as deploy, so only the deploy-owned
# root must pre-exist. web/ is pre-made so caddy's bind mount can't grab it as root.
docker network inspect vibes_net >/dev/null 2>&1 || \
	docker network create --subnet 10.200.200.0/24 vibes_net
mkdir -p /opt/vibes/web
chown -R deploy:deploy /opt/vibes

# --- weekly docker image GC (catches orphans from removed apps) ---
cat > /etc/systemd/system/docker-prune.service <<'EOF'
[Unit]
Description=Prune unused docker images older than 30d
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker image prune -af --filter until=720h
EOF

cat > /etc/systemd/system/docker-prune.timer <<'EOF'
[Unit]
Description=Weekly docker image prune

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now docker-prune.timer

echo "bootstrap done."
