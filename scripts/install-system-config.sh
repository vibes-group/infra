#!/bin/sh
set -eu

root=${ROOT_DIR:-}
systemctl_cmd=${SYSTEMCTL:-systemctl}

if [ "${1:-}" = "--bootstrap" ]; then
	[ "$#" -eq 2 ] || exit 2
	source_dir=$2
else
	[ "$#" -eq 1 ] || exit 2
	source_dir=$1
	release=${source_dir##*/}
	[ "${#release}" -eq 40 ] || exit 2
	case "$release" in *[!0-9a-f]*) exit 2 ;; esac
	[ "$source_dir" = "/opt/vibes/system-config/$release" ] || exit 2
	[ "$(realpath "$source_dir")" = "$source_dir" ] || exit 2
fi

if [ -z "$root" ] && [ "$(id -u)" -ne 0 ]; then
	echo "must run as root" >&2
	exit 1
fi

required_files='scripts/install-system-config.sh
scripts/reboot-if-idle.sh
system/apt/20auto-upgrades.conf
system/apt/51docker-upgrades.conf
system/apt/52autoreboot.conf
system/sudoers/vibes-system-config
system/systemd/apt-daily.timer.d/vibes.conf
system/systemd/apt-daily-upgrade.timer.d/vibes.conf
system/systemd/vibes-reboot-if-idle.service
system/systemd/vibes-reboot-if-idle.timer'
printf '%s\n' "$required_files" | while IFS= read -r file; do
	[ -f "$source_dir/$file" ] && [ ! -L "$source_dir/$file" ] || {
		echo "invalid system config file: $file" >&2
		exit 1
	}
done

if [ -z "$root" ]; then
	visudo -cf "$source_dir/system/sudoers/vibes-system-config" >/dev/null
fi

install -D -m 0755 "$source_dir/scripts/reboot-if-idle.sh" "$root/usr/local/sbin/vibes-reboot-if-idle"
install -D -m 0644 "$source_dir/system/apt/20auto-upgrades.conf" "$root/etc/apt/apt.conf.d/20auto-upgrades"
install -D -m 0644 "$source_dir/system/apt/51docker-upgrades.conf" "$root/etc/apt/apt.conf.d/51docker-upgrades.conf"
install -D -m 0644 "$source_dir/system/apt/52autoreboot.conf" "$root/etc/apt/apt.conf.d/52autoreboot.conf"
install -D -m 0440 "$source_dir/system/sudoers/vibes-system-config" "$root/etc/sudoers.d/vibes-system-config"
install -D -m 0644 "$source_dir/system/systemd/apt-daily.timer.d/vibes.conf" "$root/etc/systemd/system/apt-daily.timer.d/vibes.conf"
install -D -m 0644 "$source_dir/system/systemd/apt-daily-upgrade.timer.d/vibes.conf" "$root/etc/systemd/system/apt-daily-upgrade.timer.d/vibes.conf"
install -D -m 0644 "$source_dir/system/systemd/vibes-reboot-if-idle.service" "$root/etc/systemd/system/vibes-reboot-if-idle.service"
install -D -m 0644 "$source_dir/system/systemd/vibes-reboot-if-idle.timer" "$root/etc/systemd/system/vibes-reboot-if-idle.timer"
install -D -m 0755 "$source_dir/scripts/install-system-config.sh" "$root/usr/local/sbin/vibes-install-system-config"

if [ -z "$root" ]; then
	apt-config dump >/dev/null
	systemd-analyze verify /etc/systemd/system/vibes-reboot-if-idle.service /etc/systemd/system/vibes-reboot-if-idle.timer
	"$systemctl_cmd" daemon-reload
	"$systemctl_cmd" restart apt-daily.timer apt-daily-upgrade.timer
	"$systemctl_cmd" enable --now vibes-reboot-if-idle.timer
fi
