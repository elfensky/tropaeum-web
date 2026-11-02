# Requirements: tropaeum-web

**Defined:** 2026-11-02
**Core Value:** tropaeum.app stays up and trustworthy: the coming-soon page loads, sends the intended headers, and every change reaches production only through the pinned, revertible CI pipeline.

## v1 Requirements

Maintenance milestone. Sources: `.planning/codebase/CONCERNS.md` and `.planning/research/SUMMARY.md` (2026-11-02). The tracker has no open issue or milestone.

### Pull-request checks

- [ ] **CI-01**: A pull request runs a check workflow that builds the image, with no registry login and no push
- [ ] **CI-02**: The check runs the image with `ROBOTS_TAG` at its default and with `ROBOTS_TAG=` (explicit empty), and asserts the full header set and the `robots.txt` answer on `/`, `/robots.txt` and a 404 path in both modes
- [ ] **CI-03**: The check runs `nginx -t` through the image entrypoint and waits for the container to report `healthy`
- [ ] **CI-04**: The check validates `deploy/production/compose.yaml` as a Swarm stack file and asserts exactly one `image: ghcr.io/elfensky/tropaeum-web:` line
- [ ] **CI-05**: The check lints every workflow with a pinned `actionlint`
- [ ] **CI-06**: The behavioural checks live in one script a maintainer can run on a laptop with the same result as CI

### Supply chain

- [ ] **SUP-01**: Every third-party action in `.github/workflows/` is pinned to a full commit SHA with a `# vX.Y.Z` comment
- [ ] **SUP-02**: Dependabot opens pull requests for action updates; none merges without a human
- [ ] **SUP-03**: The `nginx` base image is pinned to a version tag plus digest
- [ ] **SUP-04**: The `cloudflared` image is pinned to a version tag plus digest, matching the version running in production at the time of the pin
- [ ] **SUP-05**: Dependabot opens pull requests for `nginx` and `cloudflared` updates and ignores the CI-owned `ghcr.io/elfensky/tropaeum-web` line

### Tunnel health

- [ ] **TUN-01**: `cloudflared` has an exec-form healthcheck that fails while the tunnel holds no edge connection
- [ ] **TUN-02**: A `cloudflared` update whose tasks never become healthy rolls back on its own (a `monitor` window longer than interval × retries)

### Headers

- [ ] **HDR-01**: Every response carries a Content-Security-Policy that blocks scripts and external requests and still lets the page render with its own styles and favicon
- [ ] **HDR-02**: Responses do not disclose the nginx version (`server_tokens off`)
- [ ] **HDR-03**: HSTS is sent without `preload`; `includeSubDomains` stays only after the owner confirms every `tropaeum.app` DNS name serves HTTPS

### Image and runtime

- [ ] **IMG-01**: nginx starts on a host without IPv6: the unused `listen [::]:80` is gone and the image HEALTHCHECK targets `127.0.0.1`, in the same change
- [ ] **IMG-02**: The Docker build context holds only the files the image copies (allow-list `.dockerignore`)

### Repo governance and runbook

- [ ] **OPS-01**: A ruleset on the `deploy` branch blocks deletion and force pushes, and the CI pin job still pushes after it is on
- [ ] **OPS-02**: The README holds a runbook: create and rotate the tunnel secret, the node label, the Arcane Git Sync settings, rollback, a dead-tunnel signal, and a `curl -I` header check; no secret values

### Page metadata

- [ ] **META-01**: The page has a meta description and a canonical URL
- [ ] **META-02**: The page has Open Graph and Twitter text tags, so a shared link shows a title and description
- [ ] **META-03**: The site serves a favicon that loads under the CSP

## v2 Requirements

Deferred. Tracked but not in the current roadmap.

### Pipeline

- **PIPE-01**: The build on `main` runs the same checks before the pin (`deploy.yml` calls the check workflow)
- **PIPE-02**: `main` requires the check workflow to pass before merge
- **PIPE-03**: Commits that touch only `.planning/**` do not rebuild and re-pin production (`paths-ignore`)
- **PIPE-04**: `zizmor` workflow audit, `persist-credentials: false` on non-pushing jobs, and the repo setting that requires SHA-pinned actions
- **PIPE-05**: The pin step pins the app image by digest, not by tag

### Hardening

- **HARD-01**: The `deploy` branch accepts pushes from CI only (GitHub App token as the ruleset bypass actor)
- **HARD-02**: An unset `ROBOTS_TAG` fails closed (today it fails open: no `X-Robots-Tag`, `robots.txt` 404)
- **HARD-03**: Container runtime hardening for `web` (read-only root filesystem, dropped capabilities)

### Page

- **PAGE-01**: An `og:image` share image (1200×630), once the owner supplies one

## Out of Scope

| Feature | Reason |
|---------|--------|
| The Tropaeum app (trophy tracking, PlayStation/Xbox/Steam, Discord sharing, purchases) | Separate product; not in this repo |
| Accounts, backend, database, mailing list, sign-up form | None exists; the tracker asks for none |
| Analytics, tracking, third-party scripts, external requests | The site promises none |
| `<meta name="robots">`, JSON-LD, `sitemap.xml` | The indexing switch lives in the header only; one page needs no sitemap |
| Auto-merge of dependency pull requests | A merge to `main` is a production deploy |
| Blocking vulnerability-scan gate, monitoring stack, staging stack, cosign signing | Out of proportion for one static page |
| Manual `docker stack deploy` or live-system changes from a planning session | The pin pipeline is the only deploy path |
| arm64 build | The production swarm is all amd64 |
| Infrastructure outside the repo (Zero Trust hostnames, Arcane settings, swarm nodes) | Owned elsewhere; the runbook records it, the repo does not manage it |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CI-01 | Phase 1 | Pending |
| CI-02 | Phase 1 | Pending |
| CI-03 | Phase 1 | Pending |
| CI-04 | Phase 1 | Pending |
| CI-05 | Phase 1 | Pending |
| CI-06 | Phase 1 | Pending |
| SUP-01 | Phase 2 | Pending |
| SUP-02 | Phase 2 | Pending |
| SUP-03 | Phase 2 | Pending |
| SUP-04 | Phase 2 | Pending |
| SUP-05 | Phase 2 | Pending |
| HDR-01 | Phase 3 | Pending |
| HDR-02 | Phase 3 | Pending |
| HDR-03 | Phase 3 | Pending |
| IMG-01 | Phase 3 | Pending |
| IMG-02 | Phase 3 | Pending |
| TUN-01 | Phase 4 | Pending |
| TUN-02 | Phase 4 | Pending |
| META-01 | Phase 5 | Pending |
| META-02 | Phase 5 | Pending |
| META-03 | Phase 5 | Pending |
| OPS-01 | Phase 6 | Pending |
| OPS-02 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 23
- Unmapped: 0 ✓

---
*Requirements defined: 2026-11-02*
*Last updated: 2026-11-02 after roadmap creation*
