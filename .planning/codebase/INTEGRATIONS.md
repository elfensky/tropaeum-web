---
last_mapped_commit: 005b0e436c23ae67685b4e1b1bc09779227824a8
last_mapped_at: 2026-11-02
---
# External Integrations

**Analysis Date:** 2026-11-02

## APIs & External Services

**Page content:**
- None. `index.html` makes no network requests at runtime: no `<script>`, no external CSS, fonts, images, or iframes. The only outbound link is a plain anchor to `https://lav.ren` (`index.html`).
- Fonts: none loaded; the page uses the system font stack (`system-ui, sans-serif`).

**Build and deploy services:**
- GitHub Actions - CI runner for `.github/workflows/deploy.yml` (triggered by push to `main` and `workflow_dispatch`)
  - Actions used: `actions/checkout@v4`, `docker/setup-buildx-action@v3`, `docker/login-action@v3`, `docker/build-push-action@v6`
- Cloudflare Tunnel - ingress for the production site. Connector image `cloudflare/cloudflared:latest` in `deploy/production/compose.yaml`. Tunnel name: `tropaeum.app (production)` (remotely managed in the Zero Trust dashboard).
  - Auth: tunnel token, read from Swarm secret `tropaeum_cloudflared` via `TUNNEL_TOKEN_FILE`
  - Public hostnames (apex and `www`) map to `http://web:80`. These live in the Cloudflare Zero Trust dashboard, not in the repo.
- Arcane Git Sync - external tool that applies `deploy/production/compose.yaml` from the `deploy` branch to the Swarm. Its configuration is not in this repo.

## Data Storage

**Databases:**
- Not applicable. No database client, connection string, or schema exists in the repo.

**File Storage:**
- Local filesystem only, inside the container: `/usr/share/nginx/html/` holds `index.html`.

**Container Registry:**
- GitHub Container Registry, `ghcr.io/elfensky/tropaeum-web`
  - Written by: `.github/workflows/deploy.yml` (`build` job) with `GITHUB_TOKEN`, `packages: write`
  - Tags: `sha-<commit>` on every build; `sha-unpinned` placeholder on `main` only
  - Read by: the Swarm nodes that run the `web` service

**Caching:**
- GitHub Actions cache (`cache-from` / `cache-to: type=gha`) for Docker layers in `.github/workflows/deploy.yml`
- No application cache

## Authentication & Identity

**Auth Provider:**
- None for end users. The site is public.
- Operator and CI identity:
  - GitHub Actions `GITHUB_TOKEN` for `ghcr.io` login (`docker/login-action@v3`) and for pushing the `deploy` branch (`contents: write`, `pin` job)
  - Commit identity `github-actions[bot]` for pin commits (`.github/workflows/deploy.yml`)
  - Cloudflare Tunnel token as Swarm secret `tropaeum_cloudflared` (`deploy/production/compose.yaml`)

## Monitoring & Observability

**Error Tracking:**
- None detected

**Logs:**
- nginx default access and error logs (container stdout/stderr, via `nginx -g "daemon off;"` in `Dockerfile`)
- Docker Swarm service logs (no log driver configured in `deploy/production/compose.yaml`)

**Health:**
- Container `HEALTHCHECK` in `Dockerfile`: `wget -qO- http://localhost/` every 30s
- Swarm rollout gated by the same health check (`update_config.order: start-first`, `failure_action: rollback`, `monitor: 30s`) in `deploy/production/compose.yaml`

## CI/CD & Deployment

**Hosting:**
- Self-managed Docker Swarm, stack `tropaeum`, nodes labelled `role=apps`
- Public domain: `tropaeum.app` (apex and `www`), served through Cloudflare Tunnel

**CI Pipeline:**
- GitHub Actions workflow `Build and pin` in `.github/workflows/deploy.yml`
  - Job `build`: builds `linux/amd64` image from `Dockerfile`, pushes to `ghcr.io/<repo>:sha-<commit>`, passes `COMMIT_SHA` build arg
  - Job `pin` (only on `main`): renders `deploy/production/compose.yaml` with the `sha-<commit>` tag via `sed`, verifies the pin with `grep`, and commits it to the `deploy` branch (up to 3 attempts)
  - Concurrency group `build-${{ github.ref }}`, `cancel-in-progress: false`
  - Path filter: root `*.md` changes do not trigger the workflow

**Rollback:**
- `git revert` of a pin commit on the `deploy` branch, then Arcane Git Sync applies it (`README.md`)

## Environment Configuration

**Required env vars (container):**
- `ROBOTS_TAG` - default `noindex, nofollow` in `Dockerfile`; set to `''` in production (`deploy/production/compose.yaml`)
- `TUNNEL_TOKEN_FILE` - `/run/secrets/tropaeum_cloudflared` for the `cloudflared` service

**Required secrets (Swarm and CI):**
- Swarm secret `tropaeum_cloudflared` - must exist on a manager before the stack deploys (`deploy/production/compose.yaml` header comment)
- `GITHUB_TOKEN` - provided automatically by GitHub Actions

**Secrets location:**
- Cloudflare Tunnel token: Swarm secret store (external). Not stored in git.
- GitHub Actions tokens: GitHub-managed, per workflow run.
- No `.env` file is tracked in the repo. Local `.env*` files were not read.

## Webhooks & Callbacks

**Incoming:**
- None in the repo. The GitHub push event starts the workflow (`.github/workflows/deploy.yml`, `on: push`); no endpoint is defined here.

**Outgoing:**
- Pushes to `ghcr.io` (image) and to the `deploy` branch of this GitHub repository (`.github/workflows/deploy.yml`)
- Arcane Git Sync polls or receives updates from the `deploy` branch. Its trigger mechanism is outside this repo.

---

*Integration audit: 2026-11-02*
