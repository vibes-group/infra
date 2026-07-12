#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
EOF
chmod +x "$tmp/systemctl"

ROOT_DIR="$tmp/root" SYSTEMCTL="$tmp/systemctl" SYSTEMCTL_LOG="$tmp/systemctl.log" \
	"$repo/scripts/install-system-config.sh" --bootstrap "$repo"

cmp "$repo/scripts/reboot-if-idle.sh" "$tmp/root/usr/local/sbin/vibes-reboot-if-idle"
cmp "$repo/scripts/install-system-config.sh" "$tmp/root/usr/local/sbin/vibes-install-system-config"
cmp "$repo/system/apt/52autoreboot.conf" "$tmp/root/etc/apt/apt.conf.d/52autoreboot.conf"
cmp "$repo/system/systemd/vibes-reboot-if-idle.timer" "$tmp/root/etc/systemd/system/vibes-reboot-if-idle.timer"
test ! -e "$tmp/systemctl.log"

if ROOT_DIR="$tmp/invalid-root" "$repo/scripts/install-system-config.sh" "$repo" >/dev/null 2>&1; then
	echo "installer accepted a non-release source" >&2
	exit 1
fi

mkdir "$tmp/broken"
cp -R "$repo/scripts" "$repo/system" "$tmp/broken/"
rm "$tmp/broken/system/apt/52autoreboot.conf"
if ROOT_DIR="$tmp/broken-root" "$repo/scripts/install-system-config.sh" --bootstrap "$tmp/broken" >/dev/null 2>&1; then
	echo "installer accepted an incomplete config" >&2
	exit 1
fi

cat >"$tmp/root/etc/systemd/system/docker.service" <<'EOF'
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vibes-reboot-if-idle
EOF
printf '[Unit]\n' >"$tmp/root/etc/systemd/system/sysinit.target"
printf '[Unit]\n' >"$tmp/root/etc/systemd/system/timers.target"
systemd-analyze verify --root="$tmp/root" \
	"$tmp/root/etc/systemd/system/vibes-reboot-if-idle.service" \
	"$tmp/root/etc/systemd/system/vibes-reboot-if-idle.timer"
systemd-analyze calendar '*-*-* 00..02:00/15' --iterations=2 >/dev/null

echo "system config installer tests passed"
