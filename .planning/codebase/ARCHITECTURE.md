---
last_mapped_commit: 005b0e436c23ae67685b4e1b1bc09779227824a8
last_mapped_at: 2026-11-02
---
<!-- refreshed: 2026-11-02 -->
# Architecture

**Analysis Date:** 2026-11-02

## System Overview

```text
┌─────────────────────────────────────────────────────────────┐
│                 Visitor browser (public internet)            │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS (TLS terminated at Cloudflare)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Cloudflare Tunnel "tropaeum.app (production)"               │
│  Service `cloudflared` (2 replicas)                          │
│  `deploy/production/compose.yaml`                            │
└──────────────────────────┬──────────────────────────────────┘
                           │ http://web:80 on overlay `internal`
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Service `web` (2 replicas, nginx:1-alpine)                  │
│  `Dockerfile` + `deploy/nginx.conf`                          │
│  Serves `/usr/share/nginx/html/index.html`                   │
└─────────────────────────────────────────────────────────────┘

Build and deploy path (not a runtime layer):

┌─────────────────────────────────────────────────────────────┐
│  git push to `main`                                          │
│  `.github/workflows/deploy.yml`                              │
│   job `build`: image ghcr.io/elfensky/tropaeum-web:sha-<sha> │
│   job `pin`:   write image tag into compose, commit to       │
│                branch `deploy` (CI is sole writer)           │
└──────────────────────────┬──────────────────────────────────┘
                           │ Arcane Git Sync reads `deploy`
                           ▼
                 Docker Swarm stack `tropaeum`
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| Static page | The only content: a coming-soon page with inline CSS, no scripts | `index.html` |
| Image build | Installs the server config and the page on `nginx:1-alpine`, sets fail-closed env defaults, runs a healthcheck | `Dockerfile` |
| Web server config | Security headers, gzip, robots handling, static file serving | `deploy/nginx.conf` |
| Production stack | Swarm services `web` and `cloudflared`, placement, rollout policy, resource limits, `ROBOTS_TAG: ''` | `deploy/production/compose.yaml` |
| Build and pin pipeline | Builds and pushes the image per commit, pins the tag into the production compose on the `deploy` branch | `.github/workflows/deploy.yml` |
| Documentation | Describes deployment, rollback, local run | `README.md` |

## Pattern Overview

**Overall:** Static site served by a single stateless web server container, with GitOps-style deployment. Git is the deploy record: the image tag in the `deploy` branch defines what runs.

**Key Characteristics:**
- No application code, no build step for assets, no runtime dependencies beyond the nginx image. `index.html` contains no scripts and makes no external requests (`README.md`).
- The image is immutable and per commit: each push to `main` produces `sha-<commit>`.
- Config is applied at container start. `deploy/nginx.conf` is an nginx template. The nginx image entrypoint runs `envsubst` on it and writes `/etc/nginx/conf.d/default.conf` (`Dockerfile` comments).
- Ingress has no published ports. `cloudflared` dials out to Cloudflare, and the public hostnames route to `http://web:80` over the overlay network `internal`.
- Two replicas of each service run with `start-first` rollout and automatic rollback on failure.

## Layers

**Content layer:**
- Purpose: The page a visitor sees.
- Location: `index.html`
- Contains: HTML, one inline `<style>` block with light and dark colors via `prefers-color-scheme`.
- Depends on: Nothing. The page loads no external assets.
- Used by: nginx, through the image `COPY` at `/usr/share/nginx/html/`.

**Web server layer:**
- Purpose: Serve static files with security headers and robots policy.
- Location: `deploy/nginx.conf` (installed as `/etc/nginx/templates/default.conf.template` by `Dockerfile`)
- Contains: One `server` block on port 80. A `location = /robots.txt` block with an `if ($robots_tag)` check. A catch-all `location /` with `try_files`.
- Depends on: `ROBOTS_TAG` environment variable at container start.
- Used by: Container healthcheck and external traffic through `cloudflared`.

**Image layer:**
- Purpose: Package the server config and content into one image.
- Location: `Dockerfile`
- Contains: `FROM nginx:1-alpine`, removal of the stock `conf.d/default.conf`, template and content copies, `ENV ROBOTS_TAG="noindex, nofollow"`, `HEALTHCHECK` using `wget` against `http://localhost/`, `STOPSIGNAL SIGQUIT`.
- Depends on: `deploy/nginx.conf`, `index.html`.
- Used by: `.github/workflows/deploy.yml` (build job), and local `docker build`.

**Deployment layer:**
- Purpose: Describe and roll out the production stack.
- Location: `deploy/production/compose.yaml`
- Contains: Overlay network `internal`, external secret `tropaeum_cloudflared`, services `web` and `cloudflared`.
- Depends on: The image produced by the build job. The external Swarm secret, which is created outside the repo.
- Used by: Arcane Git Sync on the `deploy` branch.

**Pipeline layer:**
- Purpose: Turn a commit on `main` into a pinned deployment.
- Location: `.github/workflows/deploy.yml`
- Contains: Job `build` (checkout, buildx, GHCR login, build and push `linux/amd64`, with GHA cache). Job `pin` (`needs: build`, runs only on `main`, renders the compose file with `sed`, verifies the pin, commits to `deploy`).
- Depends on: `Dockerfile`, `deploy/production/compose.yaml`.
- Used by: Push events to `main`, and `workflow_dispatch`.

## Data Flow

### Primary Request Path (visitor)

1. A browser requests `https://tropaeum.app/` or `https://www.tropaeum.app/`. Cloudflare terminates TLS (Zero Trust dashboard hostname mapping, `deploy/production/compose.yaml` header comment).
2. The `cloudflared` task forwards the request to `http://web:80` on overlay network `internal`. The name `web` resolves to a healthy `web` task (`deploy/production/compose.yaml`).
3. nginx matches `location /` and uses `try_files $uri $uri/ =404`. For `/`, it serves `index.html` through `index index.html;` (`deploy/nginx.conf`).
4. Responses carry the headers set in `deploy/nginx.conf`. In production, `X-Robots-Tag` is omitted because `ROBOTS_TAG` is empty.

### Robots Request Path

1. A crawler requests `/robots.txt`.
2. `location = /robots.txt` checks `$robots_tag`.
3. Image default (`ROBOTS_TAG` set): returns `User-agent: *` and `Disallow: /`.
4. Production (`ROBOTS_TAG` empty): `try_files $uri =404` returns 404, because no robots file exists in the image (`deploy/nginx.conf` comments).

### Deploy Path (commit to running container)

1. Push to `main` (paths other than root `*.md` trigger the workflow; `.github/workflows/deploy.yml`).
2. Job `build` builds `Dockerfile` with `COMMIT_SHA` build arg and pushes `ghcr.io/elfensky/tropaeum-web:sha-<sha>`.
3. Job `pin` checks that `deploy/production/compose.yaml` contains the `image: ghcr.io/elfensky/tropaeum-web:` line. It replaces the tag with `sha-<sha>`, then commits the rendered file to branch `deploy` at path `deploy/production/compose.yaml`.
4. Arcane Git Sync applies the `deploy` branch to the Swarm stack `tropaeum`.
5. Swarm starts new tasks first (`order: start-first`). It rolls back on failure (`failure_action: rollback`, `monitor: 30s`).

**State Management:**
- The app is stateless. Each `web` task serves the same baked-in files.
- The only persistent state is git history: `main` for source, and `deploy` for the active image tag. Rollback is a `git revert` of a pin commit on `deploy` (`README.md`).
- The Cloudflare tunnel token lives in the Swarm secret `tropaeum_cloudflared`, not in the compose spec.

## Key Abstractions

**Environment-driven robots switch:**
- Purpose: Choose between indexable and keep-out behavior with one variable.
- Examples: `Dockerfile` (`ENV ROBOTS_TAG="noindex, nofollow"`), `deploy/nginx.conf` (`add_header X-Robots-Tag "${ROBOTS_TAG}"`, `if ($robots_tag)`), `deploy/production/compose.yaml` (`ROBOTS_TAG: ''`).
- Pattern: Fail-closed default in the image. The production stack opts out with an empty value.

**Pinned image tag:**
- Purpose: Make one commit map to one image and one deployment.
- Examples: `.github/workflows/deploy.yml` (`tags: ghcr.io/${{ github.repository }}:sha-${{ github.sha }}`, `sed` pin step), `deploy/production/compose.yaml` (`image: ghcr.io/elfensky/tropaeum-web:sha-unpinned`).
- Pattern: `main` carries a placeholder tag that is never deployed. The `deploy` branch carries the real tag.

**Template-rendered server config:**
- Purpose: Inject runtime values into nginx config without a custom entrypoint.
- Examples: `Dockerfile` (`COPY deploy/nginx.conf /etc/nginx/templates/default.conf.template`), `deploy/nginx.conf` (`${ROBOTS_TAG}`).
- Pattern: The nginx image's `envsubst` step. Only defined variables are substituted, so `$uri` and similar nginx variables stay intact (`Dockerfile` comment).

## Entry Points

**HTTP entry (runtime):**
- Location: `deploy/nginx.conf`, `server` block, `listen 80 default_server;`
- Triggers: Requests from `cloudflared` on the `internal` overlay network. Local requests when run with `docker run -p 8080:80` (`README.md`).
- Responsibilities: Serve `index.html`, `robots.txt`, and return 404 otherwise.

**Container start:**
- Location: `Dockerfile`, `CMD ["nginx", "-g", "daemon off;"]`
- Triggers: `docker run` or Swarm task start.
- Responsibilities: Run the nginx image entrypoint (`envsubst`, config write), then start nginx in the foreground.

**Build pipeline entry:**
- Location: `.github/workflows/deploy.yml`
- Triggers: `push` to `main` excluding root `*.md`, or `workflow_dispatch`.
- Responsibilities: Build and push the image, then pin the tag on `deploy`.

**Stack entry:**
- Location: `deploy/production/compose.yaml`
- Triggers: Arcane Git Sync on the `deploy` branch.
- Responsibilities: Define services, network, secret, and rollout policy.

## Architectural Constraints

- **Threading:** Not applicable. nginx runs its own worker model. No application code runs in the repo.
- **Global state:** None in the repo. Runtime state is the `ROBOTS_TAG` environment variable.
- **Circular imports:** Not applicable. There is no code module graph.
- **Single writer for `deploy`:** CI is the only writer of the `deploy` branch (`deploy/production/compose.yaml` header, `.github/workflows/deploy.yml`). Manual edits to the image line are not allowed.
- **Header inheritance in nginx:** No `add_header` may appear inside a `location` block. nginx drops server-level `add_header` directives in a location that declares its own (`deploy/nginx.conf` comment). Security headers would be lost.
- **Architecture of the image:** `linux/amd64` only (`.github/workflows/deploy.yml`, `shortcut:` comment). The production swarm is amd64.
- **Tunnel image tag:** The `cloudflared` service uses `cloudflare/cloudflared:latest` (`deploy/production/compose.yaml`). It is not pinned through the CI pin mechanism, unlike `web`.

## Anti-Patterns

### Editing the image line by hand

**What happens:** Someone changes `image:` in `deploy/production/compose.yaml` on `main` or on `deploy`.
**Why it's wrong:** CI overwrites the `deploy` copy on each green build of `main`. Hand edits on `main` do nothing at deploy time, and hand edits on `deploy` are lost or conflict with the next pin.
**Do this instead:** Change source files, let CI pin. To roll back, `git revert` the pin commit on `deploy` (`README.md`).

### Adding `add_header` to a location block

**What happens:** A new `location` block declares its own `add_header`.
**Why it's wrong:** nginx drops all server-level `add_header` directives in that location. The security headers and `X-Robots-Tag` disappear for that path (`deploy/nginx.conf` comment).
**Do this instead:** Put the header in the server block, or move the location's headers into the same declaration set. Keep `location` blocks header-free, as the current file does.

### Deploying with `docker stack deploy` by hand

**What happens:** An operator runs `docker stack deploy` against the production stack.
**Why it's wrong:** The stack is owned by Arcane Git Sync. A manual deploy creates drift from the `deploy` branch and breaks the git-based rollback path (`README.md`, `deploy/production/compose.yaml` header).
**Do this instead:** Roll back with a `git revert` on `deploy`.

## Error Handling

**Strategy:** Delegated to nginx and Swarm. The repo contains no application error handling.

**Patterns:**
- Unknown paths return 404 through `try_files $uri $uri/ =404;` (`deploy/nginx.conf`).
- Container health is checked every 30 seconds with `wget -qO- http://localhost/` (`Dockerfile` `HEALTHCHECK`). Swarm uses this for start-first gating.
- The deploy job fails on a non-matching pattern or an unchanged pin rather than passing silently (`.github/workflows/deploy.yml`, `grep -qE` and `grep -qF` guards).
- Failed pushes to `deploy` retry three times from a fresh copy of the branch (`.github/workflows/deploy.yml`, `publish()` loop).
- Swarm rolls back a failed `web` update (`deploy/production/compose.yaml`, `failure_action: rollback`).

## Cross-Cutting Concerns

**Logging:** Default nginx access and error logs in the container. No log configuration in the repo.
**Validation:** None in the application. The deploy job validates the pin format.
**Authentication:** None for visitors. Access to the tunnel is controlled by Cloudflare Zero Trust. The `deploy` branch write path is limited to the GitHub Actions bot (`contents: write` only on job `pin`).
**Security headers:** Set once in `deploy/nginx.conf` on the server block: `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `Strict-Transport-Security`, and `X-Robots-Tag`.

---

*Architecture analysis: 2026-11-02*
