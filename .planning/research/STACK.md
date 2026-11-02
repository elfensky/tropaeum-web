# Technology Stack: maintenance milestone

**Project:** tropaeum-web (static coming-soon page, nginx, Docker Swarm, Cloudflare Tunnel, GitHub Actions, GHCR)
**Researched:** 2026-11-02
**Scope:** 8 maintenance items only. The existing system is not re-researched.
**Method:** Versions read from the GitHub and Docker Hub APIs on 2026-11-02. Behavior claims marked VERIFIED were run locally with Docker 29.9.2 against the real images and the repo's own files. Files in the repo were not changed.

Confidence key: HIGH = official docs or run locally. MEDIUM = official docs partly confirm, or one solid secondary source. LOW = not confirmed.

## Decisions at a glance

| # | Item | Decision | Confidence |
|---|------|----------|------------|
| 1 | PR checks | New `ci.yml` on `pull_request`: plain `docker build`, run twice, `curl` probes, `docker stack config`, `actionlint` + `zizmor` via pinned Docker images | HIGH |
| 2 | Action pinning | Pin to SHA with `# vX.Y.Z` comment. Use **Dependabot**, not Renovate. Turn on the repo setting "Require actions to be pinned to a full-length commit SHA" | HIGH |
| 3 | Base images | `nginx:1.30.6-alpine3.24@sha256:0e52bd05...` (stable line) and `cloudflare/cloudflared:2026.10.7@sha256:4955524a...`. Dependabot `docker` + `docker-compose` | HIGH |
| 4 | cloudflared health | Compose `healthcheck` running `cloudflared tunnel --metrics 127.0.0.1:20241 ready`, plus `TUNNEL_METRICS` set to the same address | HIGH (VERIFIED) |
| 5 | Headers | `server_tokens off`; CSP with a style hash; HSTS `max-age=31536000` only (drop `preload`; drop `includeSubDomains` unless confirmed) | HIGH |
| 6 | `.dockerignore` / ruleset | Allow-list `.dockerignore`. Ruleset on `deploy`: block deletion and force push now. "Only Actions may push" needs a GitHub App, because `GITHUB_TOKEN` cannot be a bypass actor | HIGH for `.dockerignore`, MEDIUM for ruleset detail |
| 7 | Page metadata | description, canonical, Open Graph, Twitter card, `theme-color`, SVG + ICO + apple-touch icon. `og:image` needs a PNG | MEDIUM |
| 8 | IPv6 listen | **Delete** `listen [::]:80`. Then change the `HEALTHCHECK` host from `localhost` to `127.0.0.1` in the same commit | HIGH (VERIFIED) |

**eli14 summary.** The site is a small shop sign. Today three things can change under the sign without anyone touching it: the tools that build it, the base image, and the tunnel program. This milestone fixes each tool to an exact version with a fingerprint (the SHA or digest). A robot (Dependabot) then proposes each upgrade as a pull request. A test run (the PR checks) opens the shop in both modes before any change goes live. Blast radius today: a bad upstream release can change production on the next restart. After this milestone: a change reaches production only after a human merges a reviewed pull request.

## Recommended Stack

### CI and lint tools (items 1, 2)

| Tool | Version (2026-11-02) | Purpose | Why |
|------|----------------------|---------|-----|
| GitHub-hosted runner | `ubuntu-26.04` (explicit label) | Run all jobs | `ubuntu-latest` is migrating from 24.04 to 26.04 between 2026-10-19 and 2026-11-19. A floating label can change between two runs. Pin the label; fall back to `ubuntu-24.04` if 26.04 breaks something. MEDIUM |
| `docker build` (plain CLI) | Docker on runner | Build image for PR checks | One tiny image, no cache needed. Skips `setup-buildx`, `build-push-action` and the GHA cache (zizmor flags the GHA cache as a cache-poisoning risk). HIGH |
| `docker stack config -c <file>` | Docker CLI 29.x | Validate the Swarm stack file | VERIFIED: exits 0 on the real `compose.yaml` without a Swarm; exits 1 on an unknown key. Stricter for Swarm than `docker compose config`, which prints `deploy.placement ... only honored by the Swarm scheduler` warnings. HIGH |
| actionlint | `rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667` | Lint workflow YAML, expressions, shell (shellcheck inside) | VERIFIED: image runs on the repo and exits 0. Run with `docker run --rm -v "$PWD:/repo" -w /repo <image> -color`. HIGH |
| zizmor | `ghcr.io/zizmorcore/zizmor:1.31.1@sha256:42d409dbb851d4c5d35a058cf042b828bea1e3f2884378c526eb0974780e18d9` | Security lint for workflows | VERIFIED on the repo: reports 5 `unpinned-uses` errors and 2 `artipacked` warnings today. It is the enforcement for item 2. Run with `--no-online-audits` (no token needed) or give it `GITHUB_TOKEN` for online audits. HIGH |
| curl | preinstalled on runner | Probe `/`, `/robots.txt`, headers | No install. HIGH |

Why run actionlint and zizmor as `docker run` and not as marketplace actions: it adds no third-party action to pin. Trade-off: Dependabot does **not** update `docker://` or `docker run` references in workflows (its `github-actions` parser skips `docker://`, VERIFIED in dependabot-core source). The two image pins are bumped by hand when a release matters. Both linters run with `contents: read` and no secrets, so a stale pin is low risk.

### Pinned actions for `deploy.yml` and `ci.yml` (item 2)

Current releases and the commit each tag points to (read from the GitHub API 2026-11-02):

| Action | Today in repo | Current release | Pin line |
|--------|---------------|-----------------|----------|
| `actions/checkout` | `@v4` | v7.0.1 | `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1` |
| `docker/setup-buildx-action` | `@v3` | v4.4.1 | `docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1` |
| `docker/login-action` | `@v3` | v4.7.0 | `docker/login-action@81c6f93d4bc991e510b342a00b419b3bb4efc5c6 # v4.7.0` |
| `docker/build-push-action` | `@v6` | v7.4.0 | `docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0` |

Notes:
- The repo is three to four majors behind on three of four actions. Pin to the **current** release in the same change, not to the old SHA. A pin to old code keeps stale code.
- buildx v4, login v4 and build-push v7 move to the Node 24 runtime (needs runner 2.327.1+, true on GitHub-hosted runners) and remove deprecated inputs and env vars. The repo uses none of the removed names (`DOCKER_BUILD_NO_SUMMARY`, `DOCKER_BUILD_EXPORT_RETENTION_DAYS`). MEDIUM: release notes read, not run.
- `actions/checkout` v6 and later store credentials in a separate file under `$RUNNER_TEMP`. The `pin` job runs `git push` in the same job, so it should still work. The PR check cannot test the `pin` job (it only runs on `main`). Watch the first run after merge. MEDIUM.
- Add `persist-credentials: false` to the `build` job checkout and to the new CI checkouts. The `pin` job needs the credentials: suppress that zizmor finding with an inline ignore and a reason.
- Re-fetch SHAs at implementation time. New patch releases appear daily. Command: `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha` (a lightweight tag returns the commit; if the result has `type: tag`, dereference it).

### Dependency update bot (items 2, 3)

**Use Dependabot.** Reasons: it is built in (no app to install, no extra account), it covers all three needed ecosystems, it reads the `# vX.Y.Z` comment and updates SHA and comment together, and it updates `tag@sha256:` pairs. The repo is public, so version updates cost nothing.

**Do not use Renovate here.** It is the stronger tool (it can pin digests that are not pinned yet, automerge, and update `docker://` references). Latest is 44.202.1. For one Dockerfile, one compose file and one workflow, it adds an app install and a config file for no gain. Choose Renovate only if you later need `docker://` or `docker run` image bumps, or automerge of digest-only changes.

Known Dependabot limits for this repo (all handled below):
- It updates an existing digest but does not add a digest to a tag-only reference (Chainguard docs; consistent with `update_checker.rb`). The first pin is manual, which this milestone does.
- Docker and Docker Compose support cooldown `default-days` only, not the semver-specific options.
- A default 3-day cooldown applies to version updates even with no `cooldown` block (GitHub docs, 2026-11-02).
- `compose.yaml` in `deploy/production` is picked up by the `docker-compose` ecosystem (file regex matches `compose.yaml`, VERIFIED in source; the parser accepts `@sha256:` digests, VERIFIED in source).

Recommended `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
    cooldown: { default-days: 7 }
    groups:
      actions: { patterns: ["*"] }

  - package-ecosystem: docker          # Dockerfile (FROM nginx)
    directory: /
    schedule: { interval: weekly }
    cooldown: { default-days: 7 }
    ignore:
      # stay on the nginx stable line (1.30.x); move to 1.32 stable by hand (~spring 2027)
      - dependency-name: nginx
        update-types: ["version-update:semver-minor", "version-update:semver-major"]

  - package-ecosystem: docker-compose  # deploy/production/compose.yaml (cloudflared)
    directory: /deploy/production
    schedule: { interval: weekly }
    cooldown: { default-days: 7 }
    ignore:
      # CI owns this line (sha-unpinned placeholder, pinned by deploy.yml)
      - dependency-name: ghcr.io/elfensky/tropaeum-web
```

Confidence: HIGH for ecosystems and file matching. MEDIUM for the `ignore update-types` entry on `docker` (documented as generic, not tested on nginx tags; fallback: reject the PR or switch to mainline). Dependabot targets `main` only. The `deploy` branch copy is re-rendered from `main`, so a cloudflared bump on `main` reaches production through the normal pin run. Note: a compose-only change on `main` triggers `deploy.yml` (only root `*.md` is ignored), so the bump deploys after merge.

Repo setting (Settings, Actions, General): enable **"Require actions to be pinned to a full-length commit SHA"**. It makes GitHub refuse a run that uses a tag reference, including GitHub-authored actions. Reusable workflows can stay on tags. HIGH (official docs). It needs the pins to land first, or every run fails.

### Base images (item 3)

| Image | Pin | Rationale |
|-------|-----|-----------|
| nginx | `nginx:1.30.6-alpine3.24@sha256:0e52bd054126cdc040b1276c0af347aeb02a41b9cfe305d6094767ac30e97949` | The repo's `1-alpine` today resolves to mainline 1.31.8. Stable 1.30.6 gets fixes only, which gives fewer pull requests for a one-file site. The digest is the multi-arch index (VERIFIED with `imagetools inspect`), so it works on amd64 swarm nodes and on arm64 dev machines. Alpine is pinned to 3.24 (the only versioned Alpine variant on Docker Hub). Tested: the repo's template, entrypoint envsubst and `nginx -t` all work on this tag. |
| cloudflared | `cloudflare/cloudflared:2026.10.7@sha256:4955524aeaa379e154023d5a027c250f7b35041a2e7e950cf13f144bc9b9c5ba` | Latest release 2026.10.7 (2026-10-30). Date-style tags are plain versions to Dependabot. The image is distroless, runs as user 65532, entrypoint `cloudflared`, `NO_AUTOUPDATE=true`, no built-in healthcheck (all VERIFIED with `docker image inspect`). |

Both pins use `tag@digest`. The tag shows the version to a human; the digest is what is pulled. A rebuild of the same commit then gives the same base. A `git revert` of a cloudflared bump restores the exact old bytes.

Re-resolve both digests at implementation time (`docker buildx imagetools inspect <tag>`). Put a one-line comment above each pin: what it is, why stable not mainline.

Do not use: `nginx:1-alpine` (floats), `cloudflared:latest` (floats), `alpine-slim` variants (saves about 10 MB, but the image's `envsubst` template entrypoint and `wget` healthcheck are what this repo uses; test before switching), `nginxinc/nginx-unprivileged` (out of scope here; the root-user concern is its own item).

### cloudflared health signal (item 4)

Result: **YES, there is an official subcommand.** `cloudflared tunnel ready` calls `GET /ready` on the metrics server and exits 0 on HTTP 200, non-zero otherwise. It runs inside a distroless image because it needs no shell, no curl and no wget (exec-form healthcheck).

VERIFIED on 2026-11-02 with `cloudflare/cloudflared:2026.10.7` running a deliberately invalid token:
- `docker exec <c> cloudflared tunnel --metrics 127.0.0.1:20241 ready` printed `{"status":503,"readyConnections":0,...}` and exited **1**.
- `cloudflared tunnel ready` with no flag also read `TUNNEL_METRICS` from the environment and exited 1 the same way.
- `/ready` returns 200 only while at least one connection to the Cloudflare edge is registered (HTTP 200 with `readyConnections` above 0; consistent with the 503 and `readyConnections:0` seen).

Cloudflare's default metrics address is `0.0.0.0:<first free port of 20241-20245>` in containers (official docs), so the port can vary and the endpoint listens on all interfaces. Set the address explicitly to loopback.

Add to the `cloudflared` service in `compose.yaml`:

```yaml
    environment:
      TUNNEL_TOKEN_FILE: /run/secrets/tropaeum_cloudflared
      TUNNEL_METRICS: 127.0.0.1:20241
    healthcheck:
      test: ["CMD", "cloudflared", "tunnel", "--metrics", "127.0.0.1:20241", "ready"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    deploy:
      update_config:
        order: start-first
        failure_action: rollback
        monitor: 30s          # default is 5s: too short to see a failing healthcheck
```

`docker stack config` accepts this block (VERIFIED). Behavior in Swarm:
- With `start-first`, the new task must turn healthy before the old one stops, so a broken new cloudflared or a broken token no longer replaces a working tunnel.
- `monitor: 30s` matters: the default 5s window ends before three failed 30s checks. Keep the window longer than `interval x retries` or reduce `interval` to 10s.
- If the Cloudflare edge is unreachable from the node, all replicas go unhealthy and restart in a loop. Ingress is down in that case anyway, so this is acceptable.
- The healthcheck proves "connected to the edge". It does not prove "reaches `web:80`". An origin failure shows as 502 at the edge, not as a `/ready` failure. Add `web` reachability to the monitoring list; do not add it to this probe.
- The Swarm secret is read via `TUNNEL_TOKEN_FILE`; this stays unchanged.

Rejected: `curl` against `/ready` (no curl in the image); a sidecar container (extra moving part); relying on Cloudflare dashboard alerts only (does not gate a rollout).

### Header hardening (item 5)

Change `deploy/nginx.conf` (server block). VERIFIED by building the image with these edits on the pinned base and probing both modes:

```nginx
server_tokens off;   # drops the version from `Server:` and from error pages; `Server: nginx` remains

add_header Content-Security-Policy "default-src 'none'; style-src 'sha256-<hash of the <style> text>'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" always;
add_header X-Frame-Options "DENY" always;   # legacy twin of frame-ancestors
add_header Strict-Transport-Security "max-age=31536000" always;
```

**CSP.** The page has one inline `<style>` block and no scripts, so a hash is better than `'unsafe-inline'`.
- VERIFIED in headless Chrome: with the correct hash there is no console violation. With a wrong hash Chrome blocks the style and prints the expected hash.
- Compute the hash: SHA-256 of the exact text between `<style>` and `</style>` (including whitespace), base64. Value for the current `index.html`: `sha256-qp0HvOK1RuDQjONSnPaB9sq+6zHhwquCNcYVVfrMglY=`.
- Risk: any edit to the CSS changes the hash and the page loses its styles. **Make the PR check assert it**: compute the hash from `index.html` in the probe script and `grep` for it in the `Content-Security-Policy` header. That turns a silent production break into a red PR.
- `img-src 'self'` is for the favicon (item 7). Without it, `default-src 'none'` can block the icon in some browsers. Drop it if no icon ships.
- `frame-ancestors` only works as a header, not in a `<meta>` tag. Keep it in nginx.
- Check the Cloudflare dashboard that auto-injected features are off (Web Analytics beacon, Rocket Loader, email obfuscation, Zaraz). They inject scripts that this CSP will block, and they contradict "no external requests". The CSP will turn any of these into a visible console error. MEDIUM (dashboard state not visible from the repo).
- If the CSS later moves to a file (`style.css`), use `style-src 'self'` and delete the hash step.
- Existing rule stays: no `add_header` inside any `location` block (it would drop all server-level headers). The probe asserts the headers on `/`, on `/robots.txt` and on a 404.

**HSTS.** The scope decision:
- Drop `preload`. It has no effect until a manual submission, and the preload list says removal "cannot easily be undone" and can take months (hstspreload.org, read 2026-11-02). Its requirements also need every subdomain, including internal ones, on HTTPS.
- Drop `includeSubDomains` for now. With no cookies and no preload, it adds almost no protection and commits all current and future subdomains to HTTPS for a year. Re-add it when the owner has confirmed every `tropaeum.app` DNS name serves HTTPS (for example when the app subdomain exists). This is a decision for the owner: flag it in the plan.
- The header on plain HTTP port 80 is ignored by browsers. Behind the tunnel, nginx only sees HTTP, but Cloudflare serves HTTPS and passes the header through, so it works. No `map` on `X-Forwarded-Proto` is needed.
- Cloudflare can also add HSTS at the edge (SSL/TLS, Edge Certificates). Do not enable it as well; one source of truth.

Not adding: `Cross-Origin-*-Policy` headers (no cross-origin interaction on a static page, no benefit), `X-XSS-Protection` (obsolete), `Expect-CT` (retired).

### `.dockerignore` and the `deploy` ruleset (item 6)

**`.dockerignore`: use an allow-list.** VERIFIED: build succeeds and the image contains exactly `index.html` and the template.

```
*
!index.html
!deploy/nginx.conf
```

An allow-list fails closed: a new top-level file (such as `.planning/`, secrets, notes) never reaches the build context. When assets are added (item 7), add one `!` line each, or move the site files into a `public/` folder and allow `!public`. `Dockerfile` itself is still read by BuildKit even when ignored.

**Ruleset on `deploy`** (Settings, Rules, Rulesets, target branch `deploy`, enforcement Active). The repo is public, so rulesets are free.

Key finding: **`GITHUB_TOKEN` cannot be added to a ruleset bypass list.** Bypass actors can be roles, teams, GitHub Apps and deploy keys. The built-in Actions identity is not an installable app, and "Restrict updates" blocks everyone not on the bypass list (official docs: "only users with bypass permissions can push"). Secondary sources agree (GitHub community and several repos). So the rule "only Actions may write" cannot be built with the current `deploy.yml` unchanged. Two tiers:

| Tier | Rules | Cost | Result |
|------|-------|------|--------|
| **A (do now)** | Restrict deletions + Block force pushes on `deploy`. No bypass list. Keep the CI push as a normal fast-forward commit | None. The CI push is not a force push and not a deletion, so it still works | Pin history cannot be rewritten or deleted. `git revert` rollback keeps working. A human with write access can still push a normal commit |
| **B (optional)** | A + Restrict updates (+ Restrict creations) with a single GitHub App in the bypass list. `pin` job uses `actions/create-github-app-token@v3.3.0` (SHA-pin it) and `persist-credentials: false` on checkout | A new GitHub App (installed on this repo only, `contents: write`), its private key as a repo secret (store in 1Password per house rule), a changed `pin` job | Only the app can write `deploy`. The repo owner can still edit the ruleset |

Recommendation: ship **Tier A** in this milestone. Plan Tier B as its own phase, only if the owner wants humans blocked, because it adds a long-lived credential to a project whose threat model is "an accidental or unreviewed edit". Do not use a personal access token as the bypass identity. Bypass is evaluated per ruleset, and `actions/checkout` can silently override an app token with its own persisted credentials unless `persist-credentials: false` is set (secondary sources, MEDIUM).

Also worth stating in the plan: with Tier B off, `main` should get its own ruleset (require a pull request and the new `ci` check) so the PR checks actually gate merges. Branch rules for `main` are outside the eight items but make item 1 meaningful. LOW-cost, HIGH value.

### Page metadata (item 7)

For `index.html` `<head>` (all values stay static; no external requests are made by the page itself, crawlers fetch the image):

```html
<meta name="description" content="Tropaeum tracks and shares your PlayStation trophies. Coming soon.">
<link rel="canonical" href="https://tropaeum.app/">
<meta name="theme-color" content="#fafafa" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#111111" media="(prefers-color-scheme: dark)">

<meta property="og:type" content="website">
<meta property="og:site_name" content="Tropaeum">
<meta property="og:title" content="Tropaeum">
<meta property="og:description" content="PlayStation trophies, tracked and shared. Coming soon.">
<meta property="og:url" content="https://tropaeum.app/">
<meta property="og:image" content="https://tropaeum.app/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Tropaeum: PlayStation trophies, tracked and shared.">
<meta name="twitter:card" content="summary_large_image">

<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
```

Rules and reasons:
- Open Graph's four required tags are `og:title`, `og:type`, `og:image`, `og:url` (ogp.me, HIGH from the spec; the rest are recommended).
- `og:image` must be an absolute `https://` URL and a raster file (PNG or JPG), 1200 x 630. None of the common preview crawlers is documented to accept SVG, so treat SVG as unsupported. `twitter:card=summary_large_image` is needed for the large card; X falls back to OG tags for the rest. MEDIUM (secondary guides; no single official page read).
- The favicon set: SVG for modern browsers (it can carry its own dark-mode `prefers-color-scheme` CSS), a 32x32 ICO fallback (also stops the `/favicon.ico` 404 that browsers request on their own), a 180x180 PNG for iOS. Order matters: ICO first with `sizes="32x32"`, SVG last, so Chrome picks the SVG. MEDIUM (Safari SVG-favicon status conflicts between sources; the ICO and PNG cover it either way).
- Skip a web app manifest and `msapplication-*` tags: this is not an installable app.
- Canonical points to the apex. The PR and staging images also send `noindex`, so a canonical to production is harmless there.
- `<meta name="robots">` is not needed: `X-Robots-Tag` and `robots.txt` already control indexing. Do not duplicate the switch in HTML; the page is baked into the image and cannot follow the `ROBOTS_TAG` env var.
- Assets add `COPY` lines to the Dockerfile and `!` lines to `.dockerignore`. The three icon files and `og.png` are **design inputs the owner must supply**. Without a logo, ship the description, canonical and Open Graph text tags and defer `og:image` and icons.
- Adding these tags does not change the `<style>` text, so the CSP hash stays valid.

### nginx IPv6 listen (item 8)

**Decision: delete `listen [::]:80 default_server;` from `deploy/nginx.conf`, and in the same commit change the Dockerfile `HEALTHCHECK` to `127.0.0.1`.**

Evidence (all run locally, nginx 1.30.6 on Alpine 3.24):
- With `net.ipv6.conf.all.disable_ipv6=1` set by Docker, nginx **still starts** with `listen [::]:80`. The failure the CONCERNS file fears only happens when the kernel has no IPv6 at all (`ipv6.disable=1` on the boot command line, no `/proc/net/if_inet6`). That case could not be reproduced on Docker Desktop. It is real in nginx (`socket() [::]:80 failed (97: Address family not supported)`) but rare on a normal Debian/Ubuntu Swarm node.
- The official nginx image avoids the problem in its own default config with a script that checks for `/proc/net/if_inet6` before enabling the IPv6 listen. This repo deletes `default.conf` and ships its own template, so that script never touches the repo's config, and the template's unconditional `[::]` line has no guard.
- Traffic to `web` comes from `cloudflared` over the IPv4 overlay network (`http://web:80`). Nothing in the stack needs `[::]`.
- **Side effect that must be fixed:** with IPv4-only listen, the current `HEALTHCHECK wget -qO- http://localhost/` **fails**. `/etc/hosts` lists `::1 localhost`, and BusyBox `wget` tries `::1` first and does not fall back (VERIFIED: `Connection refused`, exit 1; `127.0.0.1` exits 0). The healthcheck gates `start-first` rollouts, so skipping this fix would cause a rollback loop. Verified replacement: `wget -qO /dev/null http://127.0.0.1/ || exit 1`.

Rejected alternative: keep `[::]:80` and add a `/docker-entrypoint.d/` script that inserts it only if `/proc/net/if_inet6` exists. It works, but it is more code to keep for a listener nothing uses. Choose it only if a stack later publishes port 80 to IPv6 clients directly.

The PR check covers this: starting the container and waiting for `healthy` fails if either half is missing.

## Item 1: PR-check design

Add `.github/workflows/ci.yml`. Keep it separate from `deploy.yml` so the deploy path stays untouched.

```yaml
name: CI
on:
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true        # safe here: no deploy, unlike deploy.yml
jobs:
  lint:
    runs-on: ubuntu-26.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@<sha> # v7.0.1
        with: { persist-credentials: false }
      - name: actionlint
        run: docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12@sha256:b1934ee5... -color
      - name: zizmor
        run: docker run --rm -v "$PWD:/repo" -w /repo ghcr.io/zizmorcore/zizmor:1.31.1@sha256:42d409db... --no-online-audits .
      - name: Swarm stack file
        run: docker stack config -c deploy/production/compose.yaml > /dev/null
  image:
    runs-on: ubuntu-26.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<sha> # v7.0.1
        with: { persist-credentials: false }
      - run: docker build -t tropaeum-web:ci .
      - run: ./scripts/smoke.sh tropaeum-web:ci      # see below
```

`scripts/smoke.sh` (a short shell script, runnable locally with the same command):
1. For each mode, `docker run -d --health-interval=2s -p 8080:80 [-e ROBOTS_TAG=]`: indexing off (image default) and indexing on (`-e ROBOTS_TAG=`, empty).
2. `curl --retry 10 --retry-connrefused --retry-delay 1` until `/` answers. Then wait for `docker inspect -f '{{.State.Health.Status}}'` to be `healthy`.
3. `docker exec <c> nginx -t` (after envsubst has rendered the template).
4. Assertions on `/`: status 200; body contains `<h1>Tropaeum</h1>`; headers `Content-Security-Policy`, `Strict-Transport-Security`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Frame-Options` present; `Server` header has no version digits; the CSP contains the hash computed from `index.html`.
5. Mode "noindex": `X-Robots-Tag: noindex, nofollow` on `/`; `/robots.txt` is 200 with `Disallow: /`.
6. Mode "indexable": **no** `X-Robots-Tag` header on `/`; `/robots.txt` is 404.
7. The same headers are present on a 404 (`/nope`), which guards the "no `add_header` in a location" rule.
8. `docker rm -f` in a `trap`, and `docker logs` printed on failure.

VERIFIED manually: both modes behave exactly as listed on the pinned stable image (noindex: header present, `robots.txt` 200 with `Disallow: /`; indexable: no `X-Robots-Tag`, `robots.txt` 404; `nginx -t` OK; healthcheck exit 0).

Also run, in the `lint` job: `grep` that `deploy/production/compose.yaml` has exactly one line matching `image: ghcr.io/elfensky/tropaeum-web:` (the `pin` job depends on this; today it fails only on `main`, after merge).

Do not add: `hadolint` (v2.15.1 exists; a four-instruction Dockerfile does not justify the job), `docker/build-push-action` with GHA cache in PR checks, a matrix over architectures (production is amd64 only).

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Update bot | Dependabot | Renovate (44.202.1) | Extra app and config for 3 files. Pick only for `docker://` bumps or automerge |
| Action pinning | Manual SHA + Dependabot comment updates + repo SHA policy | `pinact` / `pinata` CLI | Not needed for 4 actions; zizmor already flags unpinned ones |
| Action lint | `docker run` actionlint + zizmor, pinned by digest | Marketplace wrappers (`reviewdog/action-actionlint`, `raven-actions/actionlint`) | Adds third-party actions to pin and audit; Dependabot would track them, but they only wrap a binary |
| Stack validation | `docker stack config -c` | `docker compose config -q` | Passes the file but prints 5 Swarm-only warnings on every run; the stack parser is closer to what Swarm applies |
| nginx line | stable 1.30.x | mainline 1.31.x (`1-alpine`) | More frequent releases and PRs, no feature needed |
| cloudflared health | `tunnel ready` | `curl /ready` | No curl in distroless image |
| `deploy` branch lock | Tier A ruleset now | Tier B GitHub App bypass | New long-lived credential; defer |
| IPv6 | Remove `[::]:80` | Conditional entrypoint script | More code for an unused listener |
| CSP style | Hash | `'unsafe-inline'` | Weakens the policy for no saving; CI makes the hash cheap to keep right |
| Runner | `ubuntu-26.04` pinned label | `ubuntu-latest` | Moving label during the 24.04 to 26.04 migration window |

## What NOT to use

- `nginx:1-alpine`, `cloudflare/cloudflared:latest`, `@v4`-style action tags: all float.
- `pull_request_target` for any CI check: it runs with secrets on fork code. Use `pull_request`.
- `cancel-in-progress: true` in `deploy.yml`: the existing `false` is correct and must stay.
- A CSP with `'unsafe-inline'` or `*` sources; `Strict-Transport-Security ... preload` without a signed-off submission plan.
- `docker://` references in workflows if you expect Dependabot to bump them (it skips them).
- A personal access token as a ruleset bypass.
- Marking Alpine as `latest`-style (`alpine`) in the nginx tag: the Alpine version moves under you.

## Installation

No package manager is involved. Files to add or change:

```bash
# New
.github/workflows/ci.yml
.github/dependabot.yml
scripts/smoke.sh
.dockerignore
# Optional assets (owner supplies): favicon.ico favicon.svg apple-touch-icon.png og.png

# Edit
Dockerfile                          # FROM pin, HEALTHCHECK 127.0.0.1
deploy/nginx.conf                   # drop [::]:80, add server_tokens/CSP/HSTS change
deploy/production/compose.yaml      # cloudflared pin, healthcheck, TUNNEL_METRICS, monitor
.github/workflows/deploy.yml        # SHA pins, runner label, persist-credentials
index.html                          # metadata tags

# Repo settings (UI, not in git)
Settings > Actions > General       # require full-length SHA pinning (after pins land)
Settings > Rules > Rulesets        # deploy: restrict deletions + block force pushes
```

## Ordering constraints (for the roadmap)

1. Item 8 (IPv6 + healthcheck host) and item 3 (base image pin) change the image. Land them after the PR checks (item 1) exist, so the checks prove them.
2. Item 5's CSP hash and item 7's metadata both edit `index.html` or the header: land the CSS-hash probe in the same change as the CSP.
3. Item 2's repo setting must come last: it fails every run until all `uses:` lines are SHA-pinned.
4. Dependabot (items 2, 3) goes after the first manual pin, because it will not add digests itself.
5. Item 4 (cloudflared health) is the only change that the PR check cannot test (needs a real tunnel token). Verify it by hand on the first deploy: check `docker service ps` shows `healthy` and the old task stays until the new one is healthy.

## Open points for the owner

- HSTS `includeSubDomains`: confirm all `tropaeum.app` DNS names serve HTTPS before re-adding.
- Tier A or Tier B for the `deploy` ruleset.
- Logo, favicon and 1200x630 share image assets.
- Cloudflare dashboard: confirm Web Analytics, Rocket Loader, email obfuscation and Zaraz are off (the CSP will block them).
- Whether production nodes could ever have IPv6 disabled at kernel level (the only case where `[::]:80` truly fails).

## Sources

- GitHub REST API release and tag lookups for `actions/checkout`, `docker/*-action`, `rhysd/actionlint`, `zizmorcore/zizmor`, `cloudflare/cloudflared`, `renovatebot/renovate`, `actions/create-github-app-token` (2026-11-02). HIGH
- [Docker Hub nginx tags](https://hub.docker.com/_/nginx) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4298). HIGH
- [actionlint usage](https://raw.githubusercontent.com/rhysd/actionlint/main/docs/usage.md) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4300). HIGH
- [Dependabot supported ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4130). HIGH
- [Dependabot options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=2630). HIGH (cooldown, groups, ignore)
- dependabot-core source: `docker/lib/dependabot/docker_compose/file_fetcher.rb`, `file_parser.rb`, `github_actions/file_parser.rb` (read 2026-11-02). HIGH
- [GitHub ruleset creation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4316) and [available rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4373). HIGH
- GitHub community threads on `GITHUB_TOKEN` and ruleset bypass (Discussion 25305, 136531 and linked repos). MEDIUM (no official statement found)
- [Require SHA pinning setting](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4386). HIGH
- [Ubuntu 26 GA and `ubuntu-latest` migration](https://github.blog/changelog/2026-09-17-ubuntu-26-generally-available-and-latest-migration) (via search summary). MEDIUM
- [Cloudflare Tunnel metrics](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/monitor-tunnels/metrics/) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4339). HIGH. The `tunnel ready` subcommand is not on that page: it comes from the CLI help and local run, plus cloudflared PR #1135 (mirror). HIGH (run locally)
- [HSTS preload requirements](https://hstspreload.org/) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4313). HIGH
- Open Graph and favicon guidance: ogp.me spec (memory, HIGH) and secondary guides on image size and favicon sets. MEDIUM
- Local runs on 2026-11-02: Docker 29.9.2, Chrome headless, images `nginx:1.30.6-alpine3.24`, `cloudflare/cloudflared:2026.10.7`, `rhysd/actionlint:1.7.12`, `zizmor:1.31.1`. HIGH
