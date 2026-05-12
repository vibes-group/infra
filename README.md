# vibes-group/infra

Деплой и общая инфра для приложений `vibes-group`. Все на одном VPS, docker compose + Caddy.

> Репо публичный. В коммитах — только плейсхолдеры (`{$VAR}`, `${IMAGE_TAG}`). Реальные значения (хосты, IP, пароли, ключи) — в GitHub Secrets (org или repo).

## Структура

```
apps/<app>/compose.yml        # docker compose stack для каждого приложения
caddy/compose.yml             # Caddy reverse proxy, общий для всех аппов
caddy/Caddyfile               # vhosts, читает {$VOICE_HUB_HOST}, {$MESSAGE_HUB_HOST}
scripts/bootstrap.sh          # one-shot VPS setup (docker, ufw, sysctl, user, dirs)
.github/workflows/deploy.yml  # reusable: app repos вызывают через `uses:`
.github/workflows/redeploy.yml# manual workflow_dispatch — переключение на старый sha
.github/workflows/caddy.yml   # push в caddy/** → редеплой Caddy
Taskfile.yml                  # локальные команды: status, logs, restart
```

## Поток деплоя

```
push в <app> master
  → <app>/build.yml: build+push ghcr.io/vibes-group/<app>:<sha>
  → uses vibes-group/infra/.github/workflows/deploy.yml@master
      input: { app, image_tag }
      secrets: { DEPLOY_HOST, DEPLOY_SSH_KEY, DEPLOY_HOST_KEY, APP_HOSTNAME, ... }
  → infra/deploy.yml: scp compose, write .env, docker compose pull && up -d, health poll
```

## Сервер layout

```
/opt/vibes/
├── caddy/
│   ├── compose.yml
│   ├── Caddyfile
│   └── .env             # VOICE_HUB_HOST, MESSAGE_HUB_HOST
├── voice-hub/
│   ├── compose.yml
│   ├── .env
│   └── data/            # bind, content: HMAC, argon хеши
└── message-hub/
    └── ...
```

Общая docker network `vibes_net` (external) — caddy резолвит app-сервисы по имени.

## Bootstrap нового сервера

```
scp scripts/bootstrap.sh root@<host>:/tmp/
ssh root@<host> 'bash /tmp/bootstrap.sh'
```

Идемпотентен. После — добавить deploy pubkey в `~deploy/.ssh/authorized_keys`.

## Подключить новое приложение

1. Добавить `apps/<app>/compose.yml` (network `vibes_net`, image `ghcr.io/vibes-group/<app>:${IMAGE_TAG}`).
2. Добавить vhost в `caddy/Caddyfile` (`{$<APP>_HOST} { reverse_proxy <app>-app:8080 }`).
3. Org secret `<APP>_HOST` + repo secrets для самого аппа.
4. В app репо: `.github/workflows/build.yml` → build+push → `uses: vibes-group/infra/.github/workflows/deploy.yml@master`.
