# vibes-group/infra

Деплой и общая инфра для приложений `vibes-group`. Все на одном VPS, docker compose + Caddy.

> Репо публичный. В коммитах — только плейсхолдеры (`{$VAR}`, `${IMAGE_TAG}`). Реальные значения (хосты, IP, пароли, ключи) — в GitHub Secrets (org или repo).

## Структура

```
apps/<app>/compose.yml                # docker compose stack для каждого приложения
caddy/compose.yml                     # Caddy reverse proxy, общий для всех аппов
caddy/Caddyfile                       # vhosts, читает {$VOICE_HUB_HOST}, {$MESSAGE_HUB_HOST}
scripts/bootstrap.sh                  # one-shot VPS setup (docker, ufw, sysctl, user, dirs)
.github/actions/write-env/action.yml  # composite: app репо пишет свой .env на хост
.github/workflows/deploy.yml          # reusable: scp compose, pull, up -d, health poll
.github/workflows/deploy-static.yml   # reusable: download artifact, publish static files to /opt/vibes/web/<site>
.github/workflows/caddy.yml           # push в caddy/** → редеплой Caddy
Taskfile.yml                          # локальные команды: status, logs, restart
```

## Поток деплоя

```
push в <app> master
  → <app>/build.yml:
      job build:     build+push ghcr.io/vibes-group/<app>:<sha>
      job write-env: checkout infra → uses infra/.github/actions/write-env
                     пишет /opt/vibes/<app>/.env (имена секретов знает только app)
      job deploy:    uses infra/.github/workflows/deploy.yml@master
                     scp compose → docker compose pull && up -d → health poll
```

Статические SPA могут деплоиться отдельным artifact: app repo собирает `dist`,
а `infra/.github/workflows/deploy-static.yml` публикует его в
`/opt/vibes/web/<site>/releases/<sha>` и атомарно переключает `current`.

**Граница ответственности**: app репо владеет содержимым `.env` (свои секреты), infra владеет deploy mechanics (compose, pull, restart, health). infra не знает имён app-секретов.

## Контракт для app репо

Чтобы app задеплоился через `infra/deploy.yml`, его `apps/<app>/compose.yml` **обязан**:

1. **Иметь `healthcheck:`** у основного сервиса. Без него `docker compose ps --format "{{.Health}}"` вернёт пусто, и health poll упадёт после 60 секунд.
2. **Network `vibes_net` (external)** — иначе Caddy не достучится до контейнера.
3. **Имя сервиса = `<app>-app`** — Caddyfile ссылается на `reverse_proxy <app>-app:8080`.
4. **Использовать `${IMAGE_TAG:?...}`** для tag'а image. Значение приходит из `.env` который пишет write-env composite.

Пример минимального compose:
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

## Сервер layout

```
/opt/vibes/
├── caddy/
│   ├── compose.yml
│   ├── Caddyfile
│   ├── .env             # VOICE_HUB_HOST, MESSAGE_HUB_HOST, ...
│   └── data/            # ACME state (bind)
├── voice-hub/
│   ├── compose.yml      # из infra apps/voice-hub/
│   ├── .env             # написан write-env composite из voice-hub repo
│   └── data/            # bind, content: HMAC, argon хеши
├── web/
│   └── <site>/           # static SPA releases + current symlink, served by Caddy
└── <app>/
    └── ...
```

Общая docker network `vibes_net` (external) — Caddy резолвит app-сервисы по имени.

## Bootstrap нового сервера

```
scp scripts/bootstrap.sh root@<host>:/tmp/
ssh root@<host> 'bash /tmp/bootstrap.sh'
```

Идемпотентен. После — добавить deploy pubkey в `~deploy/.ssh/authorized_keys`.

## Подключить новое приложение

1. `apps/<app>/compose.yml` в этом репо (см. контракт выше).
2. vhost в `caddy/Caddyfile`: `{$<APP>_HOST} { reverse_proxy <app>-app:8080 }`.
3. Org secret `<APP>_HOST` (scope: infra + новый app репо).
4. В app репо `.github/workflows/build.yml`:
   - job `build`: build+push image
   - job `write-env`: `uses: vibes-group/infra/.github/actions/write-env@master`, передать свои секреты как multiline `env:` input
   - job `deploy`: `uses: vibes-group/infra/.github/workflows/deploy.yml@master`, передать только `DEPLOY_HOST`, `DEPLOY_SSH_KEY`, `DEPLOY_HOST_KEY`
5. **Не трогать** `infra/deploy.yml` или `infra/.github/actions/write-env/` — они generic.

## Откат

```
gh workflow run <build-workflow>.yml --ref <old-sha-or-tag> --repo vibes-group/<app>
```

Старый sha берётся из `git log` app репо или GHCR package versions.
