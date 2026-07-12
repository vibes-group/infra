#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"

cat >"$tmp/bin/docker" <<'EOF'
#!/bin/sh
case "$1" in
	ps)
		printf '%s\n' caddy
		;;
	exec)
		for arg in "$@"; do url=$arg; done
		case "$url" in
			*voice-hub-app*) status=$VOICE_STATUS ;;
			*sozvon-hub-app*) status=$SOZVON_STATUS ;;
		esac
		[ "$status" != unavailable ] || exit 1
		printf '%s\n' "$status"
		;;
esac
EOF
cat >"$tmp/bin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
EOF
cat >"$tmp/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/bin/docker" "$tmp/bin/systemctl" "$tmp/bin/logger"

required=$tmp/reboot-required
systemctl_log=$tmp/systemctl.log

run_case() {
	name=$1
	voice=$2
	sozvon=$3
	want_reboot=$4
	want_exit=$5
	: >"$systemctl_log"
	set +e
	PATH="$tmp/bin:$PATH" VOICE_STATUS=$voice SOZVON_STATUS=$sozvon SYSTEMCTL_LOG=$systemctl_log REBOOT_REQUIRED_FILE=$required \
		"$root/scripts/reboot-if-idle.sh" >/dev/null 2>&1
	got_exit=$?
	set -e
	if [ "$got_exit" -ne "$want_exit" ]; then
		echo "$name: exit=$got_exit, want $want_exit" >&2
		exit 1
	fi
	got_reboot=false
	grep -qx reboot "$systemctl_log" && got_reboot=true
	if [ "$got_reboot" != "$want_reboot" ]; then
		echo "$name: reboot=$got_reboot, want $want_reboot" >&2
		exit 1
	fi
}

run_case no-required idle idle false 0
touch "$required"
run_case both-idle idle idle true 0
run_case voice-active active idle false 0
run_case sozvon-active idle active false 0
run_case unavailable idle unavailable false 1

echo "reboot guard tests passed"
