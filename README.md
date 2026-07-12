# vibes-group/infra

Деплой для приложений `vibes-group`. Один сервер, docker compose + Caddy.

## Структура

```
apps/<app>/compose.yml                # stack каждого приложения
caddy/                                # reverse proxy
system/                               # apt + systemd source of truth
scripts/bootstrap.sh                  # server setup (идемпотентен)
.github/actions/write-env/            # composite: app пишет свой .env на хост
.github/workflows/deploy.yml          # reusable: scp compose, pull, up, health
.github/workflows/deploy-static.yml   # reusable: static SPA publish
.github/workflows/caddy.yml           # caddy/** → redeploy Caddy
.github/workflows/system-config.yml   # system/** → apply через ограниченный sudo
```

## Контракт app репо

`apps/<app>/compose.yml` обязан:

1. Иметь `healthcheck:` у основного сервиса.
2. Использовать external network `vibes_net`.
3. Имя сервиса = `<app>-app` (Caddyfile ссылается на него).
4. Использовать `${IMAGE_TAG:?...}` для image tag.

Пример:

```yaml
name: <app>
networks:
  default:
    name: vibes_net
    external: true
services:
  <app>-app:
    image: ghcr.io/vibes-group/<app>:${IMAGE_TAG:?IMAGE_TAG is required}
    restart: unless-stopped
    expose: ["8080"]
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

## Bootstrap

```
ssh root@<host> 'mkdir -p /tmp/vibes-bootstrap'
scp -r scripts system root@<host>:/tmp/vibes-bootstrap/
ssh root@<host> 'bash /tmp/vibes-bootstrap/scripts/bootstrap.sh'
```

После — добавить deploy pubkey в `~deploy/.ssh/authorized_keys`.
Bootstrap устанавливает единственную sudo-команду для `deploy`; последующие
изменения `system/**` применяются workflow автоматически.

## Подключить новое приложение

1. `apps/<app>/compose.yml` (см. контракт).
2. vhost в `caddy/Caddyfile`: `{$<APP>_HOST} { reverse_proxy <app>-app:8080 }`.
3. Org secret `<APP>_HOST` (scope: infra + app репо). Для `currency-hub`: `CURRENCY_HUB_HOST=currency-hub.neverx.net`.
4. В app репо workflow с jobs: `build`, `write-env` (uses `infra/.github/actions/write-env`), `deploy` (uses `infra/.github/workflows/deploy.yml`).

## Откат

```
gh workflow run <build-workflow>.yml --ref <old-sha-or-tag> --repo vibes-group/<app>
```
