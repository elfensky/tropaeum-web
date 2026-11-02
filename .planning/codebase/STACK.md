---
last_mapped_commit: 005b0e436c23ae67685b4e1b1bc09779227824a8
last_mapped_at: 2026-11-02
---
# Technology Stack

**Analysis Date:** 2026-11-02

## Languages

**Primary:**
- HTML5 - the whole site: `index.html` (37 lines, one document)
- CSS - inline `<style>` block in `index.html`, uses custom properties and a `prefers-color-scheme: dark` media query

**Secondary:**
- nginx configuration directive language - `deploy/nginx.conf` (server block, templated)
- Dockerfile syntax - `Dockerfile` (`# syntax=docker/dockerfile:1`)
- YAML - `deploy/production/compose.yaml` (Docker Swarm stack), `.github/workflows/deploy.yml` (GitHub Actions)
- Bash (inline `run:` steps) - `.github/workflows/deploy.yml`

**Not used:**
- JavaScript. `index.html` has no `<script>` element.
- Any server-side application language. The repo has no application code.

## Runtime

**Environment:**
- nginx, base image `nginx:1-alpine` (floating major tag, set in `Dockerfile`)
- Container runtime: Docker Engine, orchestrated by Docker Swarm (production stack `tropaeum`, see `deploy/production/compose.yaml`)
- Build runner: GitHub Actions `ubuntu-latest` (`.github/workflows/deploy.yml`)
- Target architecture: `linux/amd64` only (`platforms: linux/amd64` in `.github/workflows/deploy.yml`)

**Package Manager:**
- None. The repo has no `package.json`, lockfile, or dependency manifest.
- Lockfile: Not applicable

## Frameworks

**Core:**
- nginx (image `nginx:1-alpine`) - static file server; no application framework

**Testing:**
- Not detected. No test files, test config, or test scripts exist in the repo.

**Build/Dev:**
- Docker Buildx via `docker/setup-buildx-action@v3` - image build in CI (`.github/workflows/deploy.yml`)
- `docker/build-push-action@v6` - builds and pushes the image, with GitHub Actions cache (`type=gha`)
- Local build: `docker build -t tropaeum-web:local .` (documented in `README.md`)

## Key Dependencies

**Container images (the only "dependencies" in this repo):**
- `nginx:1-alpine` - base image for the `web` service (`Dockerfile`)
- `cloudflare/cloudflared:latest` - tunnel connector, `cloudflared` service (`deploy/production/compose.yaml`)
- `docker/checkout` action chain: `actions/checkout@v4`, `docker/setup-buildx-action@v3`, `docker/login-action@v3`, `docker/build-push-action@v6` (`.github/workflows/deploy.yml`)

**Critical:**
- `nginx` (via `nginx:1-alpine`) - serves every request; its `envsubst` template step generates the live server config at container start (`deploy/nginx.conf` is copied to `/etc/nginx/templates/default.conf.template`)
- `cloudflared` - the only ingress path to the site; no port is published

**Infrastructure:**
- Alpine Linux - underlying OS of the nginx image; the image's `HEALTHCHECK` uses `wget` from this base
- GitHub Container Registry (`ghcr.io/elfensky/tropaeum-web`) - image storage

## Configuration

**Environment (container runtime variables):**
- `ROBOTS_TAG` - set in `Dockerfile` to `"noindex, nofollow"` (fail-closed default); set to `''` in `deploy/production/compose.yaml`. It controls the `X-Robots-Tag` header and the `robots.txt` response in `deploy/nginx.conf`.
- `COMMIT_SHA` - Docker build argument, default `unknown`, written to the `org.opencontainers.image.revision` label (`Dockerfile`); passed from CI as `${{ github.sha }}`
- `TUNNEL_TOKEN_FILE` - set to `/run/secrets/tropaeum_cloudflared` in `deploy/production/compose.yaml`, so the tunnel token is read from a Swarm secret

**Build:**
- `Dockerfile` - single-stage image build; deletes `/etc/nginx/conf.d/default.conf`, copies the nginx template and `index.html`
- `deploy/nginx.conf` - nginx server block (gzip, security headers, `robots.txt` switch, `try_files` root)
- `.github/workflows/deploy.yml` - CI: build and push on push to `main` (paths ignore root `*.md`), then render and commit the pinned compose file to the `deploy` branch
- `deploy/production/compose.yaml` - Swarm stack definition. Its `image:` line is rewritten by CI; the copy on `main` carries the placeholder tag `sha-unpinned`.

**Secrets:**
- Swarm secret `tropaeum_cloudflared` (external, created once on a manager node). Referenced in `deploy/production/compose.yaml`. Its value is not in the repo.
- `GITHUB_TOKEN` - supplied by GitHub Actions to push to `ghcr.io` and to the `deploy` branch

## Platform Requirements

**Development:**
- Docker (with Buildx) to build and run the image locally
- Git
- No language runtime, package manager, or install step required

**Production:**
- Docker Swarm cluster with nodes labelled `role=apps` (constraint in `deploy/production/compose.yaml`)
- Swarm stack `tropaeum`, applied by Arcane Git Sync from the `deploy` branch
- Cloudflare Tunnel `tropaeum.app (production)` for ingress
- Replicas: `web` 2 (limits 0.50 CPU, 128M memory), `cloudflared` 2 (limits 0.25 CPU, 128M memory)

---

*Stack analysis: 2026-11-02*
