# tropaeum-web

## What This Is

The website of tropaeum.app. Tropaeum is an achievement-tracking app concept for trophy hunters
(PlayStation first, Xbox next, maybe Steam and others; clean UX, no ads, one-time purchase). The
app is a separate product and does not live here. This repo is the website only: today a one-page
coming-soon site on `nginx:1-alpine`, served from the production Docker Swarm since 2026-10-25
through the stack's own Cloudflare Tunnel.

## Core Value

tropaeum.app stays up and trustworthy: the coming-soon page loads, sends the intended headers, and
every change reaches production only through the pinned, revertible CI pipeline.

## Business Context

- **Customer**: trophy hunters, PlayStation first (the app's audience; the site announces it)
- **Revenue model**: the app is a one-time purchase with no ads; the website itself earns nothing
- **Success metric**: not defined yet
- **Strategy notes**: tracked in the life-cockpit vault under `#drunik` (enrollment only)

## Requirements

### Validated

- ✓ One static page (`index.html`): "Tropaeum", "PlayStation trophies, tracked and shared. Coming soon.", a link to lav.ren; no scripts, no external requests, no tracking — existing
- ✓ Light and dark colours through `prefers-color-scheme` — existing
- ✓ Image `ghcr.io/elfensky/tropaeum-web:sha-<commit>` built on every push to `main` — existing
- ✓ CI pins the image on the CI-owned `deploy` branch; Arcane Git Sync applies it; rollback is a `git revert` of the pin — existing
- ✓ Swarm stack `tropaeum` (`web` + `cloudflared`, 2 replicas each, start-first with rollback) behind its own Cloudflare Tunnel — existing
- ✓ Indexing fails closed: every container sends `X-Robots-Tag: noindex, nofollow` and a keep-out `robots.txt` unless its compose sets `ROBOTS_TAG: ''` (production does) — existing
- ✓ Server-level security headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, HSTS) and gzip — existing
- ✓ Image HEALTHCHECK on `/` gates the start-first rollout — existing

### Active

Maintenance work named in `.planning/codebase/CONCERNS.md`; the tracker has no open issue or milestone.

- [ ] Pull requests run the checks PR #1 ran by hand: image build, both indexing modes probed with `curl`, `nginx -t`, compose validation, `actionlint`
- [ ] Third-party GitHub Actions pinned to commit SHAs and kept current by a dependency bot
- [ ] Base images pinned (`nginx`, `cloudflared`) to a version or digest, and kept current
- [ ] `cloudflared` has a health signal, so a dead tunnel is detected and a bad update rolls back
- [ ] Header hardening: a Content-Security-Policy for the page, `server_tokens off`, HSTS scope confirmed for every subdomain
- [ ] Repo hygiene: a `.dockerignore`, a ruleset that keeps `deploy` CI-only, a README runbook (tunnel secret, node label, Arcane Git Sync settings)
- [ ] Page metadata for an indexable page: meta description, Open Graph tags, favicon
- [ ] The `listen [::]:80` behaviour on a host without IPv6 is tested and fixed if it fails

### Out of Scope

- The Tropaeum app (trophy tracking, PlayStation/Xbox/Steam integrations, Discord sharing, purchases) — separate product, not in this repo
- Accounts, a backend, a database, a mailing list or a sign-up form — none exists and the tracker asks for none
- Analytics, tracking, third-party scripts or external requests on the page — the site promises none
- Infrastructure outside the repo (Cloudflare Zero Trust hostnames, Arcane Git Sync settings, swarm nodes, the `deploy` branch content) — owned elsewhere; CI writes `deploy`
- A manual `docker stack deploy` or any live-system change from a planning session — the pin pipeline is the only deploy path
- An arm64 build — the production swarm is all amd64 (shortcut comment in the workflow)

## Context

- Six tracked files: `index.html`, `Dockerfile`, `deploy/nginx.conf`, `deploy/production/compose.yaml`, `.github/workflows/deploy.yml`, `README.md`. No package manifest, no tests, no linter config.
- The workflow runs on a push to `main` only, so pull requests get no CI run. PR #1 recorded manual checks: `docker build`, `docker run` in both indexing modes with `curl` probes, `docker compose config -q`, `actionlint`.
- `deploy/nginx.conf` is an envsubst template. No `add_header` may appear inside a `location`: nginx would drop every server-level header there, `X-Robots-Tag` included.
- The pin job matches the `image:` line with `grep`/`sed`; that line must carry no trailing comment.
- Codebase map: `.planning/codebase/` (2026-11-02). Concerns ranked in `CONCERNS.md`.
- PR #1 built the site "deployed like the other static sites": `deploy/nginx.conf` is lav.ren's server block without the Astro redirects, asset locations and CSP.

## Constraints

- **Tech stack**: static HTML and inline CSS on `nginx:1-alpine` — no framework, no build step, no dependency manifest
- **Privacy**: no scripts, no external requests, no tracking on the page — stated in the README
- **Deploy path**: push to `main` → CI build and pin → Arcane Git Sync; never `docker stack deploy` by hand; CI is the only writer of `deploy`
- **Indexing**: fails closed in the image; only the production compose sets `ROBOTS_TAG: ''`
- **Hosting**: production Swarm, amd64, `node.labels.role == apps`, Cloudflare Tunnel ingress, no published ports
- **Secrets**: the tunnel token is the external Swarm secret `tropaeum_cloudflared`; never in the repo
- **nginx headers**: `add_header` at server level only

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Static page on `nginx:1-alpine`, no framework | One page needs no build; same pattern as lav.ren's nginx image | ✓ Good |
| Pin the image on a CI-owned `deploy` branch; Arcane Git Sync applies it | The tag in git is the deploy; rollback is a `git revert` | ✓ Good |
| Own Cloudflare Tunnel per stack | No published ports; two connectors keep ingress when one task dies | ✓ Good |
| Indexing fails closed in the image | A copied or staging stack can never be indexed by accident | ✓ Good |
| amd64-only build | The production swarm is all amd64 | ⚠️ Revisit if a stack ever runs on the Pi swarm |
| This repo is the website only; the app is separate | Keeps the site small and its deploy path simple | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-11-02 after initialization*
