# Правила для AI-агентов

Репозиторий публичный. Не коммить реальные секреты, хосты, IP, имена пользователей, домашние пути и вывод локального окружения.

## Безопасность

- Не добавлять `.env`, токены, SSH-ключи, пароли, host keys и приватные значения из GitHub Secrets.
- В документации и примерах использовать плейсхолдеры: `<server-ip>`, `your-host.example.com`, `<app>`.
- Не хардкодить реальные prod/dev хосты или IP в workflow, compose, Caddyfile и docs.
- Перед коммитом проверять diff на секреты и реальные инфраструктурные значения.

## Git

- Коммиты по conventional commits: `fix:`, `chore:`, `docs:`, `ci:`.
- Не делать `--amend` опубликованных коммитов и `--force-push` в `master`.
- Не смешивать deploy/config changes с unrelated refactor.
- Перед PR/commit прогонять релевантную проверку: YAML syntax, compose config, или dry-run команды, если они есть.
