#!/bin/bash
# One-shot VPS bootstrap. Idempotent.
#
# Copy this file and reboot-if-idle.sh into one directory, then run as root.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)

# --- timezone: UTC on all servers (uniform logs) ---
timedatectl set-timezone UTC

# --- base system: full patch + automatic security updates ---
apt-get update
apt-get -y -o Dpkg::Options::=--force-confold dist-upgrade
apt-get install -y unattended-upgrades ufw curl ca-certificates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
# Docker's upstream repository is outside Debian's default allowed origins.
cat > /etc/apt/apt.conf.d/51docker-upgrades.conf <<'EOF'
Unattended-Upgrade::Origins-Pattern {
        "origin=Docker,label=Docker CE";
};
EOF
# Reboots are handled separately after checking both call services.
cat > /etc/apt/apt.conf.d/52autoreboot.conf <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
mkdir -p /etc/systemd/system/apt-daily.timer.d
cat > /etc/systemd/system/apt-daily.timer.d/vibes.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 22:00
RandomizedDelaySec=15m
EOF
mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
cat > /etc/systemd/system/apt-daily-upgrade.timer.d/vibes.conf <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-* 23:00
RandomizedDelaySec=15m
EOF

install -m 0755 "$script_dir/reboot-if-idle.sh" /usr/local/sbin/vibes-reboot-if-idle
cat > /etc/systemd/system/vibes-reboot-if-idle.service <<'EOF'
[Unit]
Description=Reboot after upgrades when call services are idle
After=docker.service
Requires=docker.service
ConditionPathExists=/run/reboot-required

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vibes-reboot-if-idle
EOF
cat > /etc/systemd/system/vibes-reboot-if-idle.timer <<'EOF'
[Unit]
Description=Check whether an upgrade reboot is safe

[Timer]
OnCalendar=*-*-* 00..02:00/15
RandomizedDelaySec=2m

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl restart apt-daily.timer apt-daily-upgrade.timer
systemctl enable --now vibes-reboot-if-idle.timer

# --- journald: cap disk usage ---
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf <<'EOF'
[Journal]
SystemMaxUse=200M
EOF
systemctl restart systemd-journald

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

# --- SSH hardening (key-only; drop-in so re-runs stay idempotent) ---
if ! grep -qE "^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d" /etc/ssh/sshd_config; then
	sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF
sshd -t && systemctl reload ssh

# --- vibes network + base dir ---
# CI workflows mkdir each /opt/vibes/<app> as deploy, so only the deploy-owned
# root must pre-exist. web/ is pre-made so caddy's bind mount can't grab it as root.
docker network inspect vibes_net >/dev/null 2>&1 || \
	docker network create --subnet 10.200.200.0/24 vibes_net
mkdir -p /opt/vibes/web
chown -R deploy:deploy /opt/vibes

# Image GC happens at deploy time (deploy.yml prunes after the new container is
# healthy), so no standalone timer is needed here.

echo "bootstrap done."
