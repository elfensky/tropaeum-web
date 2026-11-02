<!-- GSD:project-start source:PROJECT.md -->

## Project

**tropaeum-web**

The website of tropaeum.app. Tropaeum is an achievement-tracking app concept for trophy hunters
(PlayStation first, Xbox next, maybe Steam and others; clean UX, no ads, one-time purchase). The
app is a separate product and does not live here. This repo is the website only: today a one-page
coming-soon site on `nginx:1-alpine`, served from the production Docker Swarm since 2026-10-25
through the stack's own Cloudflare Tunnel.

**Core Value:** tropaeum.app stays up and trustworthy: the coming-soon page loads, sends the intended headers, and
every change reaches production only through the pinned, revertible CI pipeline.

### Constraints

- **Tech stack**: static HTML and inline CSS on `nginx:1-alpine` — no framework, no build step, no dependency manifest
- **Privacy**: no scripts, no external requests, no tracking on the page — stated in the README
- **Deploy path**: push to `main` → CI build and pin → Arcane Git Sync; never `docker stack deploy` by hand; CI is the only writer of `deploy`
- **Indexing**: fails closed in the image; only the production compose sets `ROBOTS_TAG: ''`
- **Hosting**: production Swarm, amd64, `node.labels.role == apps`, Cloudflare Tunnel ingress, no published ports
- **Secrets**: the tunnel token is the external Swarm secret `tropaeum_cloudflared`; never in the repo
- **nginx headers**: `add_header` at server level only

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- HTML5 - the whole site: `index.html` (37 lines, one document)
- CSS - inline `<style>` block in `index.html`, uses custom properties and a `prefers-color-scheme: dark` media query
- nginx configuration directive language - `deploy/nginx.conf` (server block, templated)
- Dockerfile syntax - `Dockerfile` (`# syntax=docker/dockerfile:1`)
- YAML - `deploy/production/compose.yaml` (Docker Swarm stack), `.github/workflows/deploy.yml` (GitHub Actions)
- Bash (inline `run:` steps) - `.github/workflows/deploy.yml`
- JavaScript. `index.html` has no `<script>` element.
- Any server-side application language. The repo has no application code.

## Runtime

- nginx, base image `nginx:1-alpine` (floating major tag, set in `Dockerfile`)
- Container runtime: Docker Engine, orchestrated by Docker Swarm (production stack `tropaeum`, see `deploy/production/compose.yaml`)
- Build runner: GitHub Actions `ubuntu-latest` (`.github/workflows/deploy.yml`)
- Target architecture: `linux/amd64` only (`platforms: linux/amd64` in `.github/workflows/deploy.yml`)
- None. The repo has no `package.json`, lockfile, or dependency manifest.
- Lockfile: Not applicable

## Frameworks

- nginx (image `nginx:1-alpine`) - static file server; no application framework
- Not detected. No test files, test config, or test scripts exist in the repo.
- Docker Buildx via `docker/setup-buildx-action@v3` - image build in CI (`.github/workflows/deploy.yml`)
- `docker/build-push-action@v6` - builds and pushes the image, with GitHub Actions cache (`type=gha`)
- Local build: `docker build -t tropaeum-web:local .` (documented in `README.md`)

## Key Dependencies

- `nginx:1-alpine` - base image for the `web` service (`Dockerfile`)
- `cloudflare/cloudflared:latest` - tunnel connector, `cloudflared` service (`deploy/production/compose.yaml`)
- `docker/checkout` action chain: `actions/checkout@v4`, `docker/setup-buildx-action@v3`, `docker/login-action@v3`, `docker/build-push-action@v6` (`.github/workflows/deploy.yml`)
- `nginx` (via `nginx:1-alpine`) - serves every request; its `envsubst` template step generates the live server config at container start (`deploy/nginx.conf` is copied to `/etc/nginx/templates/default.conf.template`)
- `cloudflared` - the only ingress path to the site; no port is published
- Alpine Linux - underlying OS of the nginx image; the image's `HEALTHCHECK` uses `wget` from this base
- GitHub Container Registry (`ghcr.io/elfensky/tropaeum-web`) - image storage

## Configuration

- `ROBOTS_TAG` - set in `Dockerfile` to `"noindex, nofollow"` (fail-closed default); set to `''` in `deploy/production/compose.yaml`. It controls the `X-Robots-Tag` header and the `robots.txt` response in `deploy/nginx.conf`.
- `COMMIT_SHA` - Docker build argument, default `unknown`, written to the `org.opencontainers.image.revision` label (`Dockerfile`); passed from CI as `${{ github.sha }}`
- `TUNNEL_TOKEN_FILE` - set to `/run/secrets/tropaeum_cloudflared` in `deploy/production/compose.yaml`, so the tunnel token is read from a Swarm secret
- `Dockerfile` - single-stage image build; deletes `/etc/nginx/conf.d/default.conf`, copies the nginx template and `index.html`
- `deploy/nginx.conf` - nginx server block (gzip, security headers, `robots.txt` switch, `try_files` root)
- `.github/workflows/deploy.yml` - CI: build and push on push to `main` (paths ignore root `*.md`), then render and commit the pinned compose file to the `deploy` branch
- `deploy/production/compose.yaml` - Swarm stack definition. Its `image:` line is rewritten by CI; the copy on `main` carries the placeholder tag `sha-unpinned`.
- Swarm secret `tropaeum_cloudflared` (external, created once on a manager node). Referenced in `deploy/production/compose.yaml`. Its value is not in the repo.
- `GITHUB_TOKEN` - supplied by GitHub Actions to push to `ghcr.io` and to the `deploy` branch

## Platform Requirements

- Docker (with Buildx) to build and run the image locally
- Git
- No language runtime, package manager, or install step required
- Docker Swarm cluster with nodes labelled `role=apps` (constraint in `deploy/production/compose.yaml`)
- Swarm stack `tropaeum`, applied by Arcane Git Sync from the `deploy` branch
- Cloudflare Tunnel `tropaeum.app (production)` for ingress
- Replicas: `web` 2 (limits 0.50 CPU, 128M memory), `cloudflared` 2 (limits 0.25 CPU, 128M memory)

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Scope of the Repository

- `index.html` - the whole site (HTML plus inline CSS, no scripts)
- `Dockerfile` - builds the image on `nginx:1-alpine`
- `deploy/nginx.conf` - server block, installed as an nginx template
- `deploy/production/compose.yaml` - Docker Swarm stack for production
- `.github/workflows/deploy.yml` - build, push, and pin workflow
- `README.md` - project overview, deploy flow, rollback, local run

## Formatting Observed Across Files

- 2 spaces in `index.html`, `deploy/nginx.conf`, `deploy/production/compose.yaml`, and `.github/workflows/deploy.yml`.
- 4 spaces inside the `<style>` block of `index.html`. Treat this as the exception: the CSS rules nest inside a `@media` block, and the file uses 4 spaces there.
- Tabs are not used.
- Comments wrap near 80 columns in `Dockerfile`, `deploy/nginx.conf`, `deploy/production/compose.yaml`, and `.github/workflows/deploy.yml`.
- Keep new comments under 80 columns to match.

## HTML and CSS (`index.html`)

- Start with lowercase `<!doctype html>` and set `<html lang="en">`.
- The `<head>` order is: `meta charset`, `meta viewport`, `meta color-scheme`, `title`, then one inline `<style>` block.
- Do not add `<script>` tags. The file states "no scripts, no external requests, no tracking" in `README.md`. Keep that rule.
- Do not load fonts, stylesheets, or images from a CDN or other external host. Use only the system font stack already set in `body`.
- Declare colours as custom properties on `:root` (`--bg`, `--fg`, `--link`). Reference them with `var(--name)`.
- Put dark-mode values in `@media (prefers-color-scheme: dark)` on `:root`. Do not hard-code colours in element rules.
- Write each declaration on one line when it fits, for example `margin: 0;`. Put a multi-property rule on separate lines when it has more than four declarations, as `body` does.
- Keep `font` as the shorthand `font: 1.125rem/1.5 system-ui, sans-serif;`.
- Use `rem` for sizes.

## nginx Configuration (`deploy/nginx.conf`)

- One `server` block. Directives come first, in this order: `listen`, `root`, `index`, then `gzip` settings, then header settings, then `location` blocks.
- Use 2-space indentation and a blank line between logical groups.
- Declare every header with `add_header <name> "<value>" always;`. The `always` flag is required so error responses carry the headers.
- Declare headers only at server level. Do not add `add_header` inside a `location`. A `location` that declares its own `add_header` drops every server-level header. The file states this rule in a comment.
- `deploy/nginx.conf` is an nginx-image template, copied to `/etc/nginx/templates/default.conf.template`. Only variables that are defined in the container environment are substituted by `envsubst`. The current variable is `${ROBOTS_TAG}`.
- Use `$robots_tag` (a `set` variable) for runtime `if` checks. Keep the template variable in the `set` line only.
- Do not add other `$` variables without defining them in the container environment. Undefined names are left as-is.

## Dockerfile

- Start with `# syntax=docker/dockerfile:1`, then a comment block that names the purpose and gives a local build command.
- Pin the base by major line: `FROM nginx:1-alpine`. Do not use `latest`.
- Put `ARG` and `LABEL` lines together after `FROM`. Use OCI label keys, for example `org.opencontainers.image.source`.
- Set safe defaults with `ENV` and document why in a comment above it. The current default is `ENV ROBOTS_TAG="noindex, nofollow"`.
- Use one `COPY` per file. Place the config under `/etc/nginx/templates/` and the site under `/usr/share/nginx/html/`.
- Use the exec form for `CMD` (`CMD ["nginx", "-g", "daemon off;"]`).
- Declare `EXPOSE 80` and `STOPSIGNAL SIGQUIT` before `HEALTHCHECK`.
- Use `HEALTHCHECK` with explicit `--interval`, `--timeout`, `--start-period`, and `--retries` flags, and end the check command with `|| exit 1`.

## Docker Swarm Stack (`deploy/production/compose.yaml`)

- The `web` service line must match the pattern `image: ghcr.io/elfensky/tropaeum-web:` exactly. The CI job searches for this pattern with `grep -qE`.
- The tag on `main` is the placeholder `sha-unpinned`. Do not replace it by hand, on `main` or on `deploy`.
- Do not put a comment on the same line as the `image:` value. The CI `sed` replaces everything after the colon.

## GitHub Actions Workflow (`.github/workflows/deploy.yml`)

- Top-level keys in order: `name`, the comment block, `on`, `permissions`, `concurrency`, `jobs`.
- Each job has `name`, `runs-on`, `timeout-minutes`, `permissions`, then `steps`.
- Give each step a `name:`. Use a comment above a step when it explains a constraint.
- Use `src=`, `publish()`, and `for ... do ... done` as the shell forms.
- Do not set `set -e`. Each failing command is guarded with `|| { ...; exit 1; }` or `|| return 1`.
- Print failures as `echo "::error::..."` and retries as `echo "::warning::..."`.
- Use `-q` on `git` commands that run in CI, and `-m` with a message for every commit.
- Write temporary files to `$RUNNER_TEMP`.

## Commit Messages

- `build:` for image and build changes (`build: coming-soon page on an nginx image`)
- `deploy:` for stack and pipeline changes (`deploy: production stack tropaeum and the pin job`)
- `chore(deploy): <env> → sha-<12 chars>` for the bot pin commits on the `deploy` branch, written by CI

## Documentation

- `README.md` is the single human-facing document. It uses `##` sections: "How it deploys", "Rollback", "Run locally".
- Root `*.md` files do not trigger a build (see `paths-ignore` in `.github/workflows/deploy.yml`).
- Inline comments are the main place where the reasons for a rule are recorded. Keep those comments accurate when a rule changes.

## Error Handling

- Configuration files fail closed by default. The image sets `ROBOTS_TAG` to `noindex, nofollow`, and only the production compose overrides it.
- CI fails loudly. Each check exits 1 with a `::error::` message. A check never passes silently when its pattern does not match.
- The pin job retries a rejected push up to three times, fetching a fresh copy of `deploy` each time and not rebasing (`publish()` in `.github/workflows/deploy.yml`).

## Secrets and Sensitive Values

- No secret values appear in tracked files. The Cloudflare tunnel token is an external Swarm secret named `tropaeum_cloudflared`, referenced by name only in `deploy/production/compose.yaml`.
- Registry login uses `${{ secrets.GITHUB_TOKEN }}`, not a stored token.
- Keep new secrets out of the repo. Reference them by name, as the compose file does.

## Naming Summary

| Kind | Convention | Example |
|------|-----------|---------|
| HTML/CSS custom property | `--kebab-case` | `--bg`, `--link` |
| nginx runtime variable | `$snake_case` | `$robots_tag` |
| nginx template variable | `${UPPER_SNAKE}` | `${ROBOTS_TAG}` |
| Compose service | lowercase, one word | `web`, `cloudflared` |
| Compose secret | `tropaeum_` prefix | `tropaeum_cloudflared` |
| Workflow job | lowercase, one word | `build`, `pin` |
| Workflow env var | `UPPER_SNAKE` | `ENV_NAME`, `IMAGE`, `SHA` |
| Shell function in `run:` | lowercase | `publish` |
| Image tag | `sha-<full commit SHA>` | `sha-005b0e4...` |
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## System Overview

```text

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

- No application code, no build step for assets, no runtime dependencies beyond the nginx image. `index.html` contains no scripts and makes no external requests (`README.md`).
- The image is immutable and per commit: each push to `main` produces `sha-<commit>`.
- Config is applied at container start. `deploy/nginx.conf` is an nginx template. The nginx image entrypoint runs `envsubst` on it and writes `/etc/nginx/conf.d/default.conf` (`Dockerfile` comments).
- Ingress has no published ports. `cloudflared` dials out to Cloudflare, and the public hostnames route to `http://web:80` over the overlay network `internal`.
- Two replicas of each service run with `start-first` rollout and automatic rollback on failure.

## Layers

- Purpose: The page a visitor sees.
- Location: `index.html`
- Contains: HTML, one inline `<style>` block with light and dark colors via `prefers-color-scheme`.
- Depends on: Nothing. The page loads no external assets.
- Used by: nginx, through the image `COPY` at `/usr/share/nginx/html/`.
- Purpose: Serve static files with security headers and robots policy.
- Location: `deploy/nginx.conf` (installed as `/etc/nginx/templates/default.conf.template` by `Dockerfile`)
- Contains: One `server` block on port 80. A `location = /robots.txt` block with an `if ($robots_tag)` check. A catch-all `location /` with `try_files`.
- Depends on: `ROBOTS_TAG` environment variable at container start.
- Used by: Container healthcheck and external traffic through `cloudflared`.
- Purpose: Package the server config and content into one image.
- Location: `Dockerfile`
- Contains: `FROM nginx:1-alpine`, removal of the stock `conf.d/default.conf`, template and content copies, `ENV ROBOTS_TAG="noindex, nofollow"`, `HEALTHCHECK` using `wget` against `http://localhost/`, `STOPSIGNAL SIGQUIT`.
- Depends on: `deploy/nginx.conf`, `index.html`.
- Used by: `.github/workflows/deploy.yml` (build job), and local `docker build`.
- Purpose: Describe and roll out the production stack.
- Location: `deploy/production/compose.yaml`
- Contains: Overlay network `internal`, external secret `tropaeum_cloudflared`, services `web` and `cloudflared`.
- Depends on: The image produced by the build job. The external Swarm secret, which is created outside the repo.
- Used by: Arcane Git Sync on the `deploy` branch.
- Purpose: Turn a commit on `main` into a pinned deployment.
- Location: `.github/workflows/deploy.yml`
- Contains: Job `build` (checkout, buildx, GHCR login, build and push `linux/amd64`, with GHA cache). Job `pin` (`needs: build`, runs only on `main`, renders the compose file with `sed`, verifies the pin, commits to `deploy`).
- Depends on: `Dockerfile`, `deploy/production/compose.yaml`.
- Used by: Push events to `main`, and `workflow_dispatch`.

## Data Flow

### Primary Request Path (visitor)

### Robots Request Path

### Deploy Path (commit to running container)

- The app is stateless. Each `web` task serves the same baked-in files.
- The only persistent state is git history: `main` for source, and `deploy` for the active image tag. Rollback is a `git revert` of a pin commit on `deploy` (`README.md`).
- The Cloudflare tunnel token lives in the Swarm secret `tropaeum_cloudflared`, not in the compose spec.

## Key Abstractions

- Purpose: Choose between indexable and keep-out behavior with one variable.
- Examples: `Dockerfile` (`ENV ROBOTS_TAG="noindex, nofollow"`), `deploy/nginx.conf` (`add_header X-Robots-Tag "${ROBOTS_TAG}"`, `if ($robots_tag)`), `deploy/production/compose.yaml` (`ROBOTS_TAG: ''`).
- Pattern: Fail-closed default in the image. The production stack opts out with an empty value.
- Purpose: Make one commit map to one image and one deployment.
- Examples: `.github/workflows/deploy.yml` (`tags: ghcr.io/${{ github.repository }}:sha-${{ github.sha }}`, `sed` pin step), `deploy/production/compose.yaml` (`image: ghcr.io/elfensky/tropaeum-web:sha-unpinned`).
- Pattern: `main` carries a placeholder tag that is never deployed. The `deploy` branch carries the real tag.
- Purpose: Inject runtime values into nginx config without a custom entrypoint.
- Examples: `Dockerfile` (`COPY deploy/nginx.conf /etc/nginx/templates/default.conf.template`), `deploy/nginx.conf` (`${ROBOTS_TAG}`).
- Pattern: The nginx image's `envsubst` step. Only defined variables are substituted, so `$uri` and similar nginx variables stay intact (`Dockerfile` comment).

## Entry Points

- Location: `deploy/nginx.conf`, `server` block, `listen 80 default_server;`
- Triggers: Requests from `cloudflared` on the `internal` overlay network. Local requests when run with `docker run -p 8080:80` (`README.md`).
- Responsibilities: Serve `index.html`, `robots.txt`, and return 404 otherwise.
- Location: `Dockerfile`, `CMD ["nginx", "-g", "daemon off;"]`
- Triggers: `docker run` or Swarm task start.
- Responsibilities: Run the nginx image entrypoint (`envsubst`, config write), then start nginx in the foreground.
- Location: `.github/workflows/deploy.yml`
- Triggers: `push` to `main` excluding root `*.md`, or `workflow_dispatch`.
- Responsibilities: Build and push the image, then pin the tag on `deploy`.
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

### Adding `add_header` to a location block

### Deploying with `docker stack deploy` by hand

## Error Handling

- Unknown paths return 404 through `try_files $uri $uri/ =404;` (`deploy/nginx.conf`).
- Container health is checked every 30 seconds with `wget -qO- http://localhost/` (`Dockerfile` `HEALTHCHECK`). Swarm uses this for start-first gating.
- The deploy job fails on a non-matching pattern or an unchanged pin rather than passing silently (`.github/workflows/deploy.yml`, `grep -qE` and `grep -qF` guards).
- Failed pushes to `deploy` retry three times from a fresh copy of the branch (`.github/workflows/deploy.yml`, `publish()` loop).
- Swarm rolls back a failed `web` update (`deploy/production/compose.yaml`, `failure_action: rollback`).

## Cross-Cutting Concerns

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-fast` for a trivial task inline, with no subagents and no PLAN.md
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
