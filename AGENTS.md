# Rules for AI agents

This repository is **public**. Treat every commit as visible.

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
