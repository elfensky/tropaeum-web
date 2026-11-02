# Project Research Summary

**Project:** tropaeum-web (website maintenance milestone; the Tropaeum app is out of scope)
**Domain:** Delivery hardening for a one-page static site: nginx image, Docker Swarm, Cloudflare Tunnel, GitHub Actions pin pipeline
**Researched:** 2026-11-02
**Confidence:** HIGH (most behavior was run locally; ruleset bypass and Dependabot detail are MEDIUM)

## Executive Summary

This is not a product build. It is eight maintenance items on a running system. The page is static, has two replicas behind a tunnel, and deploys when a human merges to `main`. The merge is the production decision. So the whole milestone has one theme: build a checker first, then use it to guard every other change. The checker is a PR workflow plus one smoke script. The script builds the image, runs it in both indexing modes, waits for `healthy`, and asserts headers on `/`, `/robots.txt` and a 404 path.

The recommended approach: pin everything that floats (actions to SHAs, nginx and cloudflared to tag plus digest), let Dependabot propose bumps, and never auto-merge. Add a cloudflared health signal (`cloudflared tunnel ready`, exec form) so a bad tunnel update rolls back. Harden nginx headers (CSP, `server_tokens off`, HSTS scope) and delete the unused IPv6 listener together with the healthcheck host change. Add page metadata, `.dockerignore` and a minimal `deploy` ruleset. Write the README runbook last.

Key risks: (1) a healthcheck or listener change that makes every task unhealthy and rolls back production; (2) probes that pass for the wrong reason (`-e ROBOTS_TAG` without `=`, probing only `/`); (3) a ruleset that blocks the `GITHUB_TOKEN` pin push; (4) a CSP that blocks its own favicon; (5) bundling the cloudflared version pin and its healthcheck in one deploy. Each has a concrete prevention below. Items 4 (cloudflared health) and the ruleset cannot be proven by CI. Both need a human check after the first real deploy.

## Key Findings

### Recommended Stack

No package manager is involved. The work is new files plus edits to six existing ones. Versions were read from the GitHub and Docker Hub APIs on 2026-11-02 and the behavior claims were run locally. Re-fetch every SHA and digest at implementation time.

**Core technologies:**
- `ci.yml` on `pull_request` (plain `docker build`, `curl` probes, `docker stack config`): the PR gate. No buildx, no cache, no login, `contents: read`.
- actionlint 1.7.12 and zizmor 1.31.1 as digest-pinned `docker run` images: lint without adding third-party actions. Trade-off: Dependabot does not bump `docker run` references, so bump these two by hand.
- Dependabot (`github-actions`, `docker`, `docker-compose`): not Renovate. Built in, covers all three ecosystems, updates SHA and comment together. Weekly, 7-day cooldown, grouped actions.
- Actions pinned to the current release, not the old major: checkout v7.0.1, setup-buildx v4.4.1, login v4.7.0, build-push v7.4.0. Repo setting "Require actions to be pinned to a full-length commit SHA" comes last.
- `nginx:1.30.6-alpine3.24@sha256:0e52bd05...` (stable line, multi-arch index digest) and `cloudflare/cloudflared:2026.10.7@sha256:4955524a...`.
- `cloudflared tunnel --metrics 127.0.0.1:20241 ready` as exec-form healthcheck (VERIFIED: exits 1 when not connected), with `TUNNEL_METRICS` set to the same address and `update_config.monitor: 30s`.
- `ubuntu-26.04` runner label pinned (`ubuntu-latest` is migrating until 2026-11-19).

### Expected Features

**Must have (table stakes, this milestone):**
- PR smoke gate: build, two indexing modes, header probes on three paths, `nginx -t`, stack-file validation, actionlint
- SHA-pinned actions plus Dependabot for actions
- Pinned nginx and cloudflared plus Dependabot `docker` and `docker-compose` (with an `ignore` for `ghcr.io/elfensky/tropaeum-web`)
- cloudflared healthcheck
- Header hardening in one change set: CSP, `server_tokens off`, HSTS scope decision, delete `listen [::]:80` plus HEALTHCHECK host fix
- Page metadata: description, canonical, Open Graph text tags, favicon
- `.dockerignore` allow-list, ruleset on `deploy` (block deletion and force push), README runbook

**Should have (add after validation):**
- Smoke gate before the pin on `main` (met by calling `ci.yml` from `deploy.yml`)
- Required status check on `main`
- `og:image` (needs a designed 1200x630 PNG from the owner)
- `persist-credentials: false`, zizmor, SHA-pin repo setting (STACK folds these in as part of the milestone; they cost little)

**Defer (v2+):**
- CI-only `deploy` through a GitHub App (Tier B ruleset)
- Digest-pinned app image in the pin step
- Container runtime hardening (read-only rootfs, `cap_drop`)
- Anti-features, do not build: analytics or tracking, sign-up form, `<meta name="robots">`, JSON-LD, sitemap, auto-merge of bot PRs, vulnerability-scan gate, monitoring stack, staging stack, cosign, conditional IPv6 entrypoint script

### Architecture Approach

One change path serves everything: PR, `ci.yml` check, human merge, `deploy.yml` (check, build and push, pin to `deploy`), Arcane Git Sync, Swarm start-first rolling update. The pin job rewrites the whole compose file from `main`, so any compose change on `main` (healthcheck, cloudflared pin) goes live on the next pin. No separate deploy step may be added.

**Major components:**
1. `ci.yml` (new) with `pull_request` and `workflow_call` triggers: the single definition of all checks, called by PRs and by `deploy.yml` (`build` gets `needs: check`). No path filter.
2. `scripts/smoke.sh` (new): takes an image ref, holds all behavioral tests, runs the same on a laptop and in CI. Each hardening change adds its own assertion.
3. `Dockerfile`, `deploy/nginx.conf`, `index.html`: image inputs. `add_header` at server level only. HEALTHCHECK host must match the nginx listen set.
4. `deploy/production/compose.yaml`: stack spec. The `web` `image:` line must stay single and comment-free for the pin job.
5. `.github/dependabot.yml` (new) and a ruleset on `deploy` (UI setting, not git).

### Critical Pitfalls

1. **Healthcheck and listener changed apart.** Removing `listen [::]:80` makes `wget http://localhost/` fail (BusyBox tries `::1` first). Change HEALTHCHECK to `127.0.0.1` in the same commit, and have the smoke script wait for `healthy`.
2. **Probes that cannot fail.** `-e ROBOTS_TAG` (no `=`) tests an unset state that fails open. Use `-e 'ROBOTS_TAG='`, assert header equality, use `set -euo pipefail`, poll health instead of `sleep`, and probe `/`, `/robots.txt` and a 404.
3. **`add_header` inside a `location`** drops every server-level header while `nginx -t` passes. Use `expires` for cache headers. The 404 probe is the guard.
4. **cloudflared healthcheck errors.** Shell form fails (distroless image). Metrics address must be fixed on loopback. `monitor` must exceed `interval x retries`. Pin the running version first, add the healthcheck in a separate deploy, so a rollback has one cause.
5. **Ruleset blocks the pin push.** `GITHUB_TOKEN` cannot be a bypass actor. Ship only "restrict deletions" and "block force pushes". Prove it with a real pin on `main`, not a no-op `workflow_dispatch`.
6. **`.dockerignore` that excludes `deploy/`** breaks `COPY deploy/nginx.conf`. Use the allow-list (`*`, `!index.html`, `!deploy/nginx.conf`).
7. **Dependabot.** Merge of a bump deploys, so no auto-merge. Ignore the app image. The first digest pin is manual.

## Implications for Roadmap

Research converges on one order. The roadmapper should keep the checker first and the governance step last. Seven phases, each one PR (phase 2 may be two).

### Phase 1: PR gate
**Rationale:** Every later change is judged by it. Dependabot PRs without it are blind merges into a branch that deploys.
**Delivers:** `.github/workflows/ci.yml` (lint job: actionlint, zizmor, `docker stack config`, a check that the compose file has exactly one `image: ghcr.io/elfensky/tropaeum-web:` line; image job: build, then `scripts/smoke.sh`), and the smoke script asserting today's behavior only.
**Addresses:** PR checks, `nginx -t`, compose validation, actionlint.
**Avoids:** Pitfalls 2, 3, 11, 12, 13, 20 (explicit `=`, three probe paths, health poll, no path filter, no login or push in PRs).

### Phase 2: Gate `main` and pin the CI supply chain
**Rationale:** `deploy.yml` calls `ci.yml` so the PR and `main` run the same checks. SHA pins and Dependabot (actions) land while the gate exists, so bot PRs are gated.
**Delivers:** `check` job and `needs: check` in `deploy.yml`; runner label `ubuntu-26.04`; all `uses:` pinned to current SHAs with `# vX.Y.Z`; `persist-credentials: false` (not on the `pin` job); `.github/dependabot.yml` with the `github-actions` entry; optionally `paths-ignore` for `.planning/**`. The repo SHA-pin setting is applied last in this phase, after pins merge.
**Avoids:** Pitfall 9 (annotated tag SHA, missing comment, unpinned linters).

### Phase 3: Base image pins, IPv6 fix, `.dockerignore`
**Rationale:** The nginx pin and the IPv6 fix both change the image, and the IPv6 reasoning depends on the pinned version. The build context change is verified by the same build.
**Delivers:** nginx tag plus digest; delete `listen [::]:80` and set HEALTHCHECK to `127.0.0.1` in one commit; allow-list `.dockerignore`; Dependabot `docker` entry (ignore nginx minor and major, stay on stable 1.30).
**Avoids:** Pitfalls 1, 4, 5, 18.

### Phase 4: Header hardening
**Rationale:** Needs the probe from Phase 1 and the pinned base from Phase 3. One commit per header, each with its assertion.
**Delivers:** `server_tokens off`; CSP; HSTS without `preload`; smoke assertions on all three paths; one browser check for CSP console errors.
**Decision for the owner/roadmapper:** The researchers split on the CSP style source. STACK recommends a style hash (`sha256-qp0HvOK1...`) with a CI assertion that recomputes it from `index.html`. FEATURES, ARCHITECTURE and PITFALLS recommend `style-src 'unsafe-inline'`. Recommended: `'unsafe-inline'` for style on a page with no scripts. It has no CSS coupling and no build machinery. The CSP still blocks every script and every external request through `default-src 'none'`. Take the hash only if the owner wants the strictest policy, and then include the CI assertion. Either way: `img-src 'self'` from day one, plus `base-uri 'none'`, `form-action 'none'`, `frame-ancestors`.
**Avoids:** Pitfalls 14, 15, 16. `includeSubDomains` stays out until the owner confirms every `tropaeum.app` DNS name serves HTTPS.

### Phase 5: cloudflared pin and health signal
**Rationale:** The only change CI cannot test. Split into two deploys so a rollback has one cause.
**Delivers:** Step A: pin the version now running (read it from a running task, expected 2026.10.7) with digest, fix the stale ENTRYPOINT comment, add the Dependabot `docker-compose` entry with the app-image `ignore`. Step B, after observing A: `TUNNEL_METRICS`, exec-form `tunnel ready` healthcheck, `start_period`, `update_config` with `order: start-first`, `failure_action: rollback`, `monitor: 30s`.
**Avoids:** Pitfalls 6, 7, 10. Verification is manual: `docker service ps` shows `healthy` and the old task stays until the new one is healthy.

### Phase 6: Page metadata
**Rationale:** Depends on the Phase 4 CSP (`img-src 'self'`) and the Phase 1 probe list (add each asset path).
**Delivers:** description, canonical, Open Graph and Twitter text tags, `theme-color`, favicon (SVG, ICO, apple-touch). `og:image` only if the owner supplies a PNG; otherwise defer it. Dockerfile `COPY` lines and `!` lines in `.dockerignore` per asset.
**Decision for the roadmapper:** The ARCHITECTURE file proposes moving the page into `site/`. STACK keeps `index.html` at the root. Recommended: keep root files plus explicit `!` lines. A `site/` move is optional and only worth it if more than a few assets arrive.
**Avoids:** Pitfalls 3, 14, 17. No `<meta name="robots">`; absolute `https://` `og:image`.

### Phase 7: Governance and runbook
**Rationale:** Last because it cannot be dry-run and its revert is a UI action. It documents the final state.
**Delivers:** ruleset on `deploy`, Tier A (block deletion and force push, no bypass list); optional `main` ruleset (require PR and the `ci` check); README runbook (tunnel secret create and rotate, node label, Arcane Git Sync settings, rollback, tunnel-dead signal, `curl -I` header check, a "last verified" date, no secret values).
**Avoids:** Pitfalls 8, 21. Prove the ruleset with a real pin on `main` and disable it first if the pin fails.

### Phase Ordering Rationale

- Phase 1 before everything: every later assertion lives in its script.
- Phase 2 before image pins: bot PRs exist only after the gate exists.
- IPv6 and nginx pin together (Phase 3): same base, one HEALTHCHECK dependency.
- Headers (4) before metadata (6): the CSP must already allow the favicon.
- cloudflared last among image work (5): version pin first, then health, each deployed alone.
- Governance last (7): only step needing a real push to prove.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 5:** needs a human to read the running cloudflared version and to check health on a real node. CI cannot prove it. Run the exact `test:` array against a throwaway container with a real token first.
- **Phase 7:** ruleset behavior for a user-owned public repo (evaluate mode, bypass) is MEDIUM. Run `/gsd-plan-phase --research-phase 7` only if Tier B is wanted.
- **Phase 4:** needs owner input (HSTS `includeSubDomains`, Cloudflare dashboard features) but no further research.

Phases with standard patterns (skip research-phase):
- **Phase 1, 2, 3, 6:** well documented, with the commands and values already run locally.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Versions from APIs; nginx, cloudflared, linters, CSP, IPv6 and healthcheck behavior run locally. Dependabot `ignore update-types` on nginx tags untested (MEDIUM) |
| Features | MEDIUM-HIGH | Repo facts HIGH. Several items superseded or confirmed by the STACK local runs (`tunnel ready`, compose file match) |
| Architecture | MEDIUM-HIGH | Pipeline and build order solid. `workflow_call` concurrency and `GITHUB_TOKEN` ruleset behavior MEDIUM |
| Pitfalls | HIGH | Most items reproduced locally. Ruleset, Dependabot digest handling and `.app` HSTS preload are MEDIUM |

**Overall confidence:** HIGH for what is buildable now. MEDIUM for governance details.

### Gaps to Address

- **Research disagreements (resolve in requirements):** CSP style source (hash vs `'unsafe-inline'`), compose validation (`docker stack config` per STACK, verified; use it, with `compose config -q` only as a fallback), `site/` folder move, and whether the linters run as `docker run` images (STACK) or a pinned action (ARCHITECTURE worry about Dependabot visibility). Recommended: `docker stack config`, `'unsafe-inline'`, root files, `docker run` with digest pins and a documented manual bump.
- **Unset `ROBOTS_TAG` fails open** (Pitfall 2, state 3). Decide whether to make the template fail closed on unset or accept it. Record as a Key Decision.
- **HSTS `includeSubDomains`:** the owner must confirm every `tropaeum.app` DNS name serves HTTPS. Note the `.app` TLD is already on the browser preload list (secondary source), so risk is low.
- **Cloudflare dashboard state:** Web Analytics, Rocket Loader, email obfuscation and Zaraz must be off or the CSP breaks them. Not visible from the repo.
- **Ruleset tier:** Tier A (now) or Tier B (GitHub App, a long-lived credential; only if humans must be blocked).
- **Assets:** logo, favicon files and a 1200x630 share image come from the owner. Without them, ship text tags only.
- **Arcane Git Sync settings:** not in the repo. The owner supplies values for the runbook.
- **Kernel IPv6:** no CI test can reproduce a kernel without IPv6. Deleting the listener removes the failure class, so no test is needed.
- **First post-merge `pin` run:** checkout v6+ changes credential storage. The PR gate cannot test the `pin` job. Watch the first run on `main`.

## Sources

### Primary (HIGH confidence)
- Local runs on 2026-11-02 (Docker 29.9.2, headless Chrome): nginx 1.30.6 and 1.31.8, cloudflared 2026.10.7, actionlint 1.7.12, zizmor 1.31.1, against the repo's own files
- GitHub REST API release and tag lookups for all pinned actions and tools
- Docker Hub nginx tags, Cloudflare Tunnel metrics docs, Dependabot supported ecosystems and options reference, GitHub ruleset docs, GitHub Actions SHA-pinning setting docs, hstspreload.org, docker-nginx entrypoint script, cloudflared Dockerfile
- dependabot-core source (file fetcher and parser for `docker-compose` and `github-actions`)

### Secondary (MEDIUM confidence)
- GitHub community threads and repos on `GITHUB_TOKEN` and ruleset bypass (no official statement)
- cloudflared mirror commits for `tunnel ready` (also confirmed by local run)
- GitHub changelog on the Ubuntu 26 migration; Open Graph and favicon guides; `.app` HSTS preload coverage

### Tertiary (LOW confidence)
- Single community issue on ruleset bypass with a PAT; Semgrep blog on org-wide SHA pinning

---
*Research completed: 2026-11-02*
*Ready for roadmap: yes*
