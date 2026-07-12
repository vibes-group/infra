#!/bin/sh
set -eu

required=${REBOOT_REQUIRED_FILE:-/run/reboot-required}

log() {
	printf '%s\n' "$1"
	logger -t vibes-reboot "$1" 2>/dev/null || true
}

check_calls() {
	caddy=$(docker ps --filter label=com.docker.compose.project=vibes-caddy --filter label=com.docker.compose.service=caddy --format '{{.ID}}' | head -n 1)
	if [ -z "$caddy" ]; then
		log "reboot deferred: caddy container is unavailable"
		return 1
	fi

	for app in voice-hub-app sozvon-hub-app; do
		if ! status=$(timeout 10 docker exec "$caddy" wget -qO- "http://$app:8081/internal/call-status"); then
			log "reboot deferred: $app call status is unavailable"
			return 1
		fi
		case "$status" in
			idle) ;;
			active)
				log "reboot deferred: $app has an active call"
				return 2
				;;
			*)
				log "reboot deferred: $app returned an invalid call status"
				return 1
				;;
		esac
	done

	log "reboot allowed: both call services are idle"
}

if [ "${1:-}" = "--check" ]; then
	check_calls
	exit $?
fi

[ -e "$required" ] || exit 0
if check_calls; then
	systemctl reboot
else
	status=$?
	[ "$status" -eq 2 ] && exit 0
	exit "$status"
fi
