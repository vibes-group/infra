#!/bin/sh
set -eu

project=ots-persistence-test
network=${project}-net
secret=persistence-probe
data=$(mktemp -d)
owner=$(id -u):$(id -g)

cleanup() {
	COMPOSE_PROJECT_NAME=$project VIBES_NETWORK_NAME=$network OTS_DATA_DIR=$data docker compose down -v >/dev/null 2>&1 || true
	docker network rm "$network" >/dev/null 2>&1 || true
	docker run --rm -e OWNER="$owner" -v "$data:/data" busybox:1.37 sh -c \
		'rm -rf /data/* /data/.[!.]* /data/..?*; chown "$OWNER" /data' >/dev/null 2>&1 || true
	rmdir "$data" 2>/dev/null || true
}
trap cleanup EXIT

docker network create "$network" >/dev/null
COMPOSE_PROJECT_NAME=$project VIBES_NETWORK_NAME=$network OTS_DATA_DIR=$data docker compose up -d --wait

request() {
	docker run --rm --network "$network" busybox:1.37 wget -qO- "$@"
}

created=$(request --header='Content-Type: application/json' --post-data="{\"secret\":\"$secret\"}" http://ots-app:3000/api/create)
id=$(printf '%s' "$created" | sed -n 's/.*"secret_id":"\([^"]*\)".*/\1/p')
test -n "$id"

COMPOSE_PROJECT_NAME=$project VIBES_NETWORK_NAME=$network OTS_DATA_DIR=$data docker compose restart ots-redis ots-app
for _ in $(seq 1 30); do
	request http://ots-app:3000/api/healthz >/dev/null 2>&1 && break
	sleep 1
done

read_back=$(request "http://ots-app:3000/api/get/$id")
printf '%s' "$read_back" | grep -Fq "\"secret\":\"$secret\""
if request "http://ots-app:3000/api/get/$id" >/dev/null 2>&1; then
	echo "secret was readable twice" >&2
	exit 1
fi

echo "OTS secret survived Redis and app restarts and remained one-time"
