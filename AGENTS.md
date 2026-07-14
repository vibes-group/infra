# Rules for AI agents

This repository is **public**. Treat every commit as visible.

## Deploy model

One server; each app is a Docker Compose stack behind Caddy, rolled out via reusable GitHub Actions workflows.

- `apps/<app>/compose.yml` — app stack (existing ones are the reference examples).
- `caddy/` — reverse proxy; `caddy.yml` redeploys it on `caddy/**`.
- `system/` — apt + systemd source of truth; `system-config.yml` only tests it. System config is root-owned and applied manually by re-running bootstrap as root.
- `deploy.yml` (reusable) — ship compose to host, pull, up, wait for health; `deploy-static.yml` — static SPA publish; `actions/write-env` — app repo writes its `.env` on the host.

## App contract

`apps/<app>/compose.yml` must:

1. Have a `healthcheck:` on the main service.
2. Use the external network `vibes_net`.
3. Name the service `<app>-app` — the Caddyfile references it.
4. Take the image tag from `${IMAGE_TAG:?...}`.

Wiring a new app: compose per contract → vhost `{$<APP>_HOST} { reverse_proxy <app>-app:8080 }` in `caddy/Caddyfile` → org secret `<APP>_HOST` with the public domain (scope: infra + app repo) → app-repo workflow with jobs `build` → `write-env` (uses `infra/.github/actions/write-env`) → `deploy` (uses `infra/.github/workflows/deploy.yml`).

## Server ops

Bootstrap: `scp -r scripts system root@<host>:/tmp/vibes-bootstrap/`, run `scripts/bootstrap.sh` as root, then add the deploy pubkey to `~deploy/.ssh/authorized_keys`. The `deploy` user has no sudo.

Rollback — rebuild and roll out an old commit:

```
gh workflow run <build-workflow>.yml --ref <old-sha-or-tag> --repo vibes-group/<app>
```

## Security

- Never commit `.env`, tokens, SSH keys, passwords, host keys, or values from GitHub Secrets.
- Use placeholders in docs: `<server-ip>`, `your-host.example.com`, `<app>`.
- Don't hardcode real prod/dev hosts or IPs in workflows, compose files, Caddyfile, or docs.
- Review the diff for secrets before committing.

## Git

- Conventional commits: `fix:`, `chore:`, `docs:`, `ci:`.
- No `--amend` on published commits, no `--force-push` to `master`.
- Don't mix deploy/config changes with unrelated refactors.
- Before commit: sanity-check YAML / compose / dry-run if applicable.
