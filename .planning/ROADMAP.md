# Roadmap: tropaeum-web

## Overview

This milestone is website maintenance only. The site is one static page on `nginx:1-alpine`, deployed when a human merges to `main`. The merge is the production decision, so the order is: build the checker first, then use it to guard every other change. Phase 1 adds the pull-request gate. Phase 2 pins everything that floats and lets Dependabot propose bumps. Phase 3 hardens the image and the response headers. Phase 4 gives the `cloudflared` tunnel a health signal. Phase 5 adds page metadata. Phase 6 protects the `deploy` branch and writes the runbook. Production changes reach the swarm only through a merge to `main` and the CI pin. No phase plans a manual `docker stack deploy`.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: PR check gate** - A pull request builds the image, probes both indexing modes and lints the workflows
- [ ] **Phase 2: Pinned supply chain** - Actions, `nginx` and `cloudflared` pinned; Dependabot proposes bumps, a human merges
- [ ] **Phase 3: Hardened image and headers** - IPv6-safe start, minimal build context, CSP, `server_tokens off`, safe HSTS
- [ ] **Phase 4: Tunnel health signal** - A dead `cloudflared` tunnel is detected and a bad update rolls back
- [ ] **Phase 5: Page metadata** - Description, canonical URL, Open Graph and Twitter text tags, favicon
- [ ] **Phase 6: Deploy branch ruleset and runbook** - `deploy` cannot be deleted or force-pushed; the README holds the runbook

## Phase Details

### Phase 1: PR check gate
**Goal:** A pull request shows the maintainer, before merge, whether the image still builds and serves the intended headers in both indexing modes.
**Mode:** mvp
**Depends on:** Nothing (first phase)
**Requirements:** CI-01, CI-02, CI-03, CI-04, CI-05, CI-06
**Success Criteria** (what must be TRUE):
  1. Opening a pull request starts a check workflow that builds the image with no registry login and no push, and the pull request shows a pass or fail result.
  2. The check runs the image with `ROBOTS_TAG` at its default and with `ROBOTS_TAG=` (explicit empty), and asserts the full header set and the `robots.txt` answer on `/`, `/robots.txt` and a 404 path in both modes. A deliberate regression, such as an `add_header` inside a `location`, makes the check fail.
  3. The check passes `nginx -t` through the image entrypoint, waits for the container to report `healthy`, validates `deploy/production/compose.yaml` as a Swarm stack file with exactly one `image: ghcr.io/elfensky/tropaeum-web:` line, and lints every workflow with a pinned `actionlint`.
  4. A maintainer runs the same smoke script on a laptop against a local image and gets the same pass or fail result as CI.
**Plans:** TBD

### Phase 2: Pinned supply chain
**Goal:** Nothing that floats can change the build or the deploy path without a reviewed, gated pull request.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements:** SUP-01, SUP-02, SUP-03, SUP-04, SUP-05
**Success Criteria** (what must be TRUE):
  1. Every third-party `uses:` line in `.github/workflows/` is a full 40-character commit SHA followed by a `# vX.Y.Z` comment, and the PR check from Phase 1 passes on the change.
  2. The `Dockerfile` `FROM nginx` line and the `cloudflared` image in `deploy/production/compose.yaml` each carry a version tag plus a digest, and the image still builds and passes the smoke script.
  3. `.github/dependabot.yml` covers GitHub Actions, the `nginx` image and the `cloudflared` image, ignores the CI-owned `ghcr.io/elfensky/tropaeum-web` line, and sets up no auto-merge. Human verification after merge: the repository's Dependabot page lists the ecosystems with no error, and the first bump pull request runs the Phase 1 check.
  4. Human verification before the pin: the owner reads the `cloudflared` version running in production (read-only) and the pin uses that version. Human verification after the first real deploy: both `cloudflared` tasks stay healthy and tropaeum.app still answers.
**Plans:** TBD

### Phase 3: Hardened image and headers
**Goal:** The image starts on any host, its build context holds only what it copies, and every response carries the intended hardening headers.
**Mode:** mvp
**Depends on:** Phase 1, Phase 2
**Requirements:** IMG-01, IMG-02, HDR-01, HDR-02, HDR-03
**Success Criteria** (what must be TRUE):
  1. The `listen [::]:80` line is gone and the image HEALTHCHECK targets `127.0.0.1`, both in one change. The container reports `healthy` in the PR check and starts without IPv6.
  2. `curl -I` against the container shows a `Content-Security-Policy` on `/`, `/robots.txt` and a 404 path. The policy blocks scripts and external requests, and a browser check shows the page renders with its own styles and no console errors.
  3. Responses show `Server: nginx` with no version number, and HSTS carries no `preload`. `includeSubDomains` stays only if the owner has confirmed that every `tropaeum.app` DNS name serves HTTPS; otherwise it is removed.
  4. The `.dockerignore` is an allow-list, so the build context holds only `index.html` and `deploy/nginx.conf`, and the image builds.
  5. Human verification after the first real deploy: `curl -I https://tropaeum.app/` shows the same headers, both `web` tasks report `healthy`, and the rollout finishes without a rollback.
**Plans:** TBD

### Phase 4: Tunnel health signal
**Goal:** The swarm detects a dead Cloudflare tunnel, and a `cloudflared` update whose tasks never become healthy rolls back on its own.
**Mode:** mvp
**Depends on:** Phase 2
**Requirements:** TUN-01, TUN-02
**Success Criteria** (what must be TRUE):
  1. The `cloudflared` service in `deploy/production/compose.yaml` has an exec-form healthcheck on a fixed loopback metrics address, and the PR check validates the stack file.
  2. The `update_config` block has `order: start-first`, `failure_action: rollback` and a `monitor` window longer than `interval` times `retries`, so a bad `cloudflared` update rolls back.
  3. Human verification before merge: the exact healthcheck command run against a throwaway local container (not the swarm) reports healthy with a valid tunnel token and unhealthy when the tunnel holds no edge connection. The token comes from 1Password and never enters the repo.
  4. Human verification after the first real deploy (a separate deploy from the Phase 2 pin): both `cloudflared` tasks report `healthy`, the old task stays until the new one is healthy, and tropaeum.app keeps answering during the rollout.
**Plans:** TBD

### Phase 5: Page metadata
**Goal:** A shared link to tropaeum.app shows a title and description, and browsers show a favicon that loads under the CSP.
**Mode:** mvp
**Depends on:** Phase 3
**Requirements:** META-01, META-02, META-03
**Success Criteria** (what must be TRUE):
  1. The page source holds a meta description and a canonical URL of `https://tropaeum.app/`.
  2. The page source holds Open Graph and Twitter text tags (title, description, type, URL), so a link preview shows a title and description. Human verification after the first real deploy: a link-preview or sharing-debugger tool shows both for tropaeum.app.
  3. The favicon path returns `200` with the right content type from the image, loads in a browser with no CSP violation in the console, and the smoke script probes it.
  4. The page still has no scripts and no external requests, and carries no `<meta name="robots">` tag.
**Plans:** TBD

### Phase 6: Deploy branch ruleset and runbook
**Goal:** The `deploy` branch cannot be deleted or force-pushed, and a maintainer can operate the stack from the README alone.
**Mode:** mvp
**Depends on:** Phase 4, Phase 5
**Requirements:** OPS-01, OPS-02
**Success Criteria** (what must be TRUE):
  1. Human verification: a ruleset on `deploy` is active, blocks deletion and force pushes, and has no bypass list. The owner applies it as a GitHub setting; the phase supplies the exact settings.
  2. Human verification: after the ruleset is on, the next real merge to `main` still produces a pin commit on `deploy` from CI, and Arcane applies it. A no-op `workflow_dispatch` run does not count as proof.
  3. The README runbook covers: create and rotate the tunnel secret, the node label, the Arcane Git Sync settings, rollback by `git revert` of the pin, the dead-tunnel signal, and a `curl -I` header check. It holds no secret values.
  4. A maintainer follows the runbook `curl -I` command and sees the headers the runbook lists.
**Plans:** TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. PR check gate | 0/TBD | Not started | - |
| 2. Pinned supply chain | 0/TBD | Not started | - |
| 3. Hardened image and headers | 0/TBD | Not started | - |
| 4. Tunnel health signal | 0/TBD | Not started | - |
| 5. Page metadata | 0/TBD | Not started | - |
| 6. Deploy branch ruleset and runbook | 0/TBD | Not started | - |
