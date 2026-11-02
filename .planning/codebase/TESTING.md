---
last_mapped_commit: 005b0e436c23ae67685b4e1b1bc09779227824a8
last_mapped_at: 2026-11-02
---
# Testing Patterns

**Analysis Date:** 2026-11-02

## Summary

**There is no test suite in this repository.** No test files, no test runner, no test framework, no assertion library, no coverage tool, and no test script exist. `git ls-files` lists six files, and none of them is a test. No `package.json`, `pytest.ini`, or similar manifest exists.

The site has no behaviour to unit-test: `index.html` contains no JavaScript. Verification is done by build, deploy-time guards, and a container healthcheck. The sections below describe what exists.

## Test Framework

**Runner:** Not detected.

**Assertion Library:** Not detected.

**Config:** Not detected.

**Run Commands:** No test command is defined in the repository. The only automated checks run in CI, as described below.

## Verification That Exists

### 1. Image build in CI

**Where:** `.github/workflows/deploy.yml`, job `build`.

**What it does:** Builds `Dockerfile` for `linux/amd64` with `docker/build-push-action@v6` and pushes `ghcr.io/elfensky/tropaeum-web:sha-<commit>`. A failed `docker build` stops the job, so the `pin` job does not run.

**What it does not do:** No step runs the built image, checks HTTP responses, validates the nginx configuration, or lints `index.html`. A build that succeeds does not prove that nginx starts with `deploy/nginx.conf`.

### 2. Pin job guards

**Where:** `.github/workflows/deploy.yml`, job `pin`, step "Render the pinned compose file".

**What it checks:**
- The source compose file contains an `image: ghcr.io/<repo>:` line. The check uses `grep -qE`. If it does not match, the job exits 1 with `::error::`.
- The rendered file names `image: ghcr.io/<repo>:sha-<commit>`. The check uses `grep -qF`. If it does not match, the job exits 1.

These guards check the text of the pin. They do not check that the compose file is valid YAML or that the stack deploys.

### 3. Commit guard on the deploy branch

**Where:** `.github/workflows/deploy.yml`, function `publish()`.

**What it checks:** `git diff --cached --quiet` skips the commit when the pinned file is unchanged, and prints `already pinned to sha-<commit>`. This prevents empty commits.

**Retry:** Three attempts. Each attempt fetches a fresh copy of `deploy` before it writes the pin.

### 4. Container healthcheck

**Where:** `Dockerfile`, `HEALTHCHECK` instruction.

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost/ >/dev/null 2>&1 || exit 1
```

**What it checks:** `GET /` on port 80 returns a successful status. It runs inside the container every 30 seconds.

**What it does not check:** Response headers, `robots.txt`, or the page content. Swarm uses this check to gate `start-first` rollouts (`deploy/production/compose.yaml`, `update_config.order: start-first` with `failure_action: rollback`).

### 5. Startup gate in the stack

**Where:** `deploy/production/compose.yaml`, service `web`.

`update_config` sets `monitor: 30s` and `failure_action: rollback`. A replica that fails its healthcheck during the monitor window triggers a rollback to the previous spec.

## Manual Verification

The `README.md` gives one local procedure:

```bash
docker build -t tropaeum-web:local .
docker run --rm -p 8080:80 -e ROBOTS_TAG='' tropaeum-web:local
```

Then open `http://localhost:8080`.

The README does not name a manual check for headers or `robots.txt`. A developer who changes `deploy/nginx.conf` can check the behaviour by hand with the same run command and `curl`:

```bash
# Default image (fails closed): expect X-Robots-Tag and a robots.txt that disallows all
docker run --rm -d -p 8081:80 --name tropaeum-noindex tropaeum-web:local
curl -sI http://localhost:8081/ | grep -i -E 'x-robots-tag|x-frame|strict-transport'
curl -s http://localhost:8081/robots.txt
docker rm -f tropaeum-noindex

# Production setting (ROBOTS_TAG empty): expect no X-Robots-Tag and robots.txt = 404
docker run --rm -d -p 8082:80 -e ROBOTS_TAG='' --name tropaeum-prod tropaeum-web:local
curl -sI http://localhost:8082/ | grep -i x-robots-tag || echo "no X-Robots-Tag (expected)"
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8082/robots.txt
docker rm -f tropaeum-prod
```

This procedure is a manual check. No script or CI step runs it.

## Test Coverage

**Requirements:** None enforced. No coverage tool is configured.

**Coverage of behaviour that matters:**

| Behaviour | Checked by | Gap |
|-----------|-----------|-----|
| Dockerfile builds | CI `build` job | None for build success |
| nginx config parses and starts | Nothing automated | The healthcheck only proves a 2xx on `/` after start |
| `X-Robots-Tag` set when `ROBOTS_TAG` non-empty | Nothing automated | Manual `curl` only |
| `X-Robots-Tag` absent when `ROBOTS_TAG=''` | Nothing automated | Manual `curl` only |
| `robots.txt` disallow vs 404 | Nothing automated | Manual `curl` only |
| Security headers present | Nothing automated | Manual `curl` only |
| `index.html` valid HTML | Nothing automated | Not checked |
| Compose file valid for Swarm | Nothing automated | Checked only at deploy by Arcane Git Sync |
| Pin line format | `grep` guards in CI `pin` job | Does not validate YAML |
| Rollback path | Manual `git revert` on `deploy` | Not tested |

## Test Types

**Unit Tests:** Not used. No code units exist.

**Integration Tests:** Not used. The closest check is the image healthcheck and the Swarm monitor window.

**E2E Tests:** Not used.

**Visual or Accessibility Tests:** Not used. The page uses `prefers-color-scheme` for dark mode, but no automated check renders it.

## Guidance for Adding Verification

The repository has no test convention to follow. If verification is added, match the existing style:

- Put any check that runs in CI inside `.github/workflows/deploy.yml`, and make it fail with `echo "::error::..."` and `exit 1`, as the `pin` job does.
- Test the nginx behaviour by running the built image, not by parsing `deploy/nginx.conf` alone. The `ROBOTS_TAG` switch depends on envsubst at container start.
- Run the check on both values of `ROBOTS_TAG`: `"noindex, nofollow"` (the image default) and `''` (production).
- Keep the check free of any external network call that a CDN or third party could change. Use `localhost` inside the container.

## Common Patterns

**Checking a rendered value in CI:**

```bash
grep -qE "^[[:space:]]*image: ${IMAGE}:" "$src" || {
  echo "::error::no 'image: ${IMAGE}:…' line in $src — refusing to pin nothing"
  exit 1
}
```

**Checking the container at runtime:**

```bash
wget -qO- http://localhost/ >/dev/null 2>&1 || exit 1
```

---

*Testing analysis: 2026-11-02*
