# Architecture Research

**Domain:** Static site on nginx, shipped as one Docker image to a Docker Swarm stack behind a Cloudflare Tunnel, built and pinned by GitHub Actions (GitOps through a CI-owned `deploy` branch)
**Milestone:** Maintenance hardening (subsequent milestone; the system already runs in production)
**Researched:** 2026-11-02
**Confidence:** MEDIUM-HIGH (repo facts HIGH; GitHub ruleset and Dependabot behaviour MEDIUM; cloudflared healthcheck wiring MEDIUM until proven on a real tunnel)

**eli14 summary.** The site is a parcel line. A person drops a parcel (a commit) at the start. A robot packs it (the build), a second robot writes the address label (the pin), and a driver (Arcane) delivers it. This milestone adds a quality check at the start of the line, a lock on the label printer's output tray, and a "is the delivery door still open?" sensor at the end. The order of work follows one rule: first build the checker, then use the checker to guard every other change. Today's blast radius is small (one static page, two replicas, start-first rollout). The risk grows only if a change reaches `main` without the checker.

## Standard Architecture

### System Overview (target state)

```
 Authors / Dependabot
        │ open PR
        ▼
┌───────────────────────────────────────────────────────────────────────┐
│ PR GATE            .github/workflows/ci.yml  (on: pull_request,        │
│                                                     workflow_call)    │
│  job lint     : actionlint, docker compose config -q                   │
│  job image    : build (load, no push, no login) → scripts/smoke.sh     │
│                  ├ nginx -t, both ROBOTS_TAG modes                     │
│                  ├ headers on /, /robots.txt, a 404 path               │
│                  ├ container reaches `healthy`                         │
│                  └ cloudflared pinned image: `tunnel ready --help`     │
│  read-only token, no secrets  → safe for Dependabot PRs                │
└──────────────────────────────┬────────────────────────────────────────┘
                               │ merge (human)
                               ▼
┌───────────────────────────────────────────────────────────────────────┐
│ main                                                                   │
│  Dockerfile (FROM nginx:<ver>@sha256)  deploy/nginx.conf  site/*       │
│  deploy/production/compose.yaml  (cloudflared:<ver>@sha256 + health)   │
└──────────────────────────────┬────────────────────────────────────────┘
                               │ push
                               ▼
┌───────────────────────────────────────────────────────────────────────┐
│ DEPLOY PIPELINE    .github/workflows/deploy.yml                        │
│  check (uses ci.yml) → build+push ghcr :sha-<commit> → pin             │
│  pin: render compose (web image line only), commit to `deploy`         │
│       with GITHUB_TOKEN (fast-forward, no force)                       │
└──────────────────────────────┬────────────────────────────────────────┘
                               │ Arcane Git Sync reads `deploy`
                               ▼
┌───────────────────────────────────────────────────────────────────────┐
│ SWARM stack `tropaeum` (rolling update, start-first, rollback)         │
│  web (2)          HEALTHCHECK → 127.0.0.1:80                           │
│  cloudflared (2)  healthcheck → `cloudflared tunnel ready` → /ready    │
└──────────────────────────────┬────────────────────────────────────────┘
                               │ outbound tunnel
                               ▼
                   Cloudflare edge → visitors

 Governance (GitHub settings, not repo files):
   ruleset on `deploy`: no deletion, no force push  (GITHUB_TOKEN cannot be a bypass actor)
   optional ruleset on `main`: PR + required check `ci`
```

### Component Responsibilities and Boundaries

| Component | Owns | Talks to | Contract it must keep |
|-----------|------|----------|-----------------------|
| `ci.yml` (new) | All pre-merge validation; one job definition used by PRs and by the deploy workflow | `Dockerfile`, `deploy/nginx.conf`, compose file, `scripts/smoke.sh` | Needs only `contents: read`. No secrets, no registry login, no push. Same checks on PR and on `main`. |
| `scripts/smoke.sh` (new) | The behavioural test of an image: `nginx -t`, both indexing modes, headers per location, health state | Docker CLI, `curl`, the image under test | Takes an image ref as argument. Runs the same on a laptop and in CI. Gains one assertion per hardening change. |
| `deploy.yml` (existing) | Build, push, pin | `ci.yml` (call), GHCR, `deploy` branch | `needs: check` gate added. Pin step unchanged. `concurrency` stays serial and never cancels. |
| `Dockerfile` | Image contents, base image pin, HEALTHCHECK | `deploy/nginx.conf`, `site/` | `FROM` is a version tag plus digest. HEALTHCHECK host matches the nginx listen set. |
| `deploy/nginx.conf` (template) | Headers, listen, robots switch, static serving | envsubst at container start | `add_header` at server level only. Only `${ROBOTS_TAG}` is substituted. No `$` in the CSP string. |
| `site/` (new, replaces root `index.html`) | Page, favicon, OG image, metadata | `Dockerfile` (`COPY site/`) | No scripts, no external requests. Inline `<style>` only. Metadata is identical in every environment. |
| `.dockerignore` (new) | Build context | Docker build | Allow-list form (`*`, then `!site`, `!deploy/nginx.conf`). |
| `deploy/production/compose.yaml` | Stack spec, `cloudflared` pin and health | Pin job (reads and rewrites one line), Arcane | The `web` `image:` line matches `^\s*image: ghcr.io/<repo>:` and carries no trailing comment. No other `image:` line may match that pattern. |
| `.github/dependabot.yml` (new) | Update PRs for actions, Dockerfile base, compose images | GitHub, PR gate | Ignores the project's own image. Never auto-merges. |
| Ruleset on `deploy` | Stops deletion and history rewrite of the deploy record | Pin job, humans doing `git revert` | Allows a plain fast-forward push by `GITHUB_TOKEN`. |
| Arcane Git Sync (external) | Applies `deploy` to Swarm | `deploy` branch, Swarm | Out of repo. Settings go into the README runbook only. |

### Data Flow

**Change flow (all maintenance features use this one path):**

1. Author or Dependabot pushes a branch and opens a PR.
2. `ci.yml` runs on the PR head. Result: a status check. No image leaves the runner.
3. A human merges. This merge is the production decision, because the push to `main` deploys.
4. `deploy.yml` runs: `check` (same `ci.yml`), then `build` (push `sha-<commit>`), then `pin`.
5. `pin` rewrites only the `web` image line of the compose file and commits the whole rendered file to `deploy`.
6. Arcane applies the file. Swarm does a start-first rolling update. A task that fails its health check inside the `monitor` window triggers rollback to the previous spec.

**Base-image update flow:** Dependabot opens a PR that edits the `FROM` line (Dockerfile) or the `cloudflared` line (compose). Step 2 builds the image on the new base and smoke-tests it. Steps 3 to 6 are unchanged. The digest or version string in git is the deploy: a `git revert` of the merge restores the exact prior bytes.

**Health signal flow (cloudflared):** `cloudflared` process, then its metrics server (`TUNNEL_METRICS=127.0.0.1:<port>`), then `/ready` (HTTP 200 only while at least one edge connection is up, else 503), then `cloudflared tunnel --metrics … ready` as exec-form healthcheck, then Docker health state, then Swarm task state. Swarm uses it two ways. During an update, start-first keeps the old task until the new task is healthy, and an unhealthy new task inside `monitor` rolls the service back. In steady state, an unhealthy task is replaced under `restart_policy: any`.

**Header flow:** `deploy/nginx.conf` template, then `COPY` into the image, then envsubst at start into `conf.d/default.conf`, then response. The smoke script reads the response, so a header lost to a location-level `add_header` fails the PR.

**Rollback flow:** `git revert` of a pin commit on `deploy` is the fast path. The next push to `main` re-renders from `main` and overwrites it, so the lasting fix is a revert on `main`. This is existing behaviour and now also covers base-image and `cloudflared` pins, because the pin commit carries the whole compose file.

## Recommended Project Structure

```
.github/
  workflows/
    ci.yml            # NEW  pull_request + workflow_call: lint, build, smoke
    deploy.yml        # existing; adds `check` job, SHA-pinned actions
  dependabot.yml      # NEW  github-actions, docker, docker-compose
  rulesets/           # NEW  optional JSON export of the `deploy` ruleset (for re-import)
scripts/
  smoke.sh            # NEW  single source of truth for image checks
deploy/
  nginx.conf          # template; hardened
  production/compose.yaml
site/                 # NEW  index.html, favicon.svg, og image
Dockerfile
.dockerignore         # NEW
README.md             # runbook added last
```

## Patterns to Follow

### Pattern 1: One check definition, two callers
**What:** `ci.yml` declares both `pull_request` and `workflow_call`. `deploy.yml` calls it with `uses: ./.github/workflows/ci.yml`, and `build` has `needs: check`.
**When:** Always. A second copy of the checks drifts from the first.
**Example:**
```yaml
# ci.yml
on:
  pull_request:          # no paths filter: a required check must always report
  workflow_call:
permissions: { contents: read }
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}   # never cancel a main run
# deploy.yml
jobs:
  check: { uses: ./.github/workflows/ci.yml }
  build: { needs: check, ... }
```
`github.event_name` inside the called workflow is the caller's event (`push`), so main runs keep the "never cancelled" rule. The caller's `permissions` cap the callee, so the top-level `contents: read` in `deploy.yml` is enough. The called workflow must not reuse the caller's concurrency group name.

### Pattern 2: Script holds the tests, workflow only calls it
**What:** `scripts/smoke.sh <image>` runs the container twice (`ROBOTS_TAG` default and `''`) and asserts. Waits for `docker inspect` health `healthy`. Probes `/`, `/robots.txt`, and `/does-not-exist`.
**When:** Always. The same script is the README's verification step.
**Example:**
```bash
for path in / /robots.txt /nope; do
  h=$(curl -sI "http://127.0.0.1:$port$path")
  for name in X-Frame-Options X-Content-Type-Options Referrer-Policy \
              Permissions-Policy Strict-Transport-Security Content-Security-Policy; do
    grep -qi "^$name:" <<<"$h" || fail "$name missing on $path"
  done
done
grep -qi '^server: nginx/' <<<"$h" && fail "version disclosed"
```

### Pattern 3: Assertion lands with the change it guards
**What:** Each hardening change edits `nginx.conf` and `smoke.sh` in the same PR. The PR proves the new assertion passes on the new config.
**When:** Every phase after the PR gate.

### Pattern 4: Build and test the exact image, then push it
**What:** On `main`, `check` builds with `load: true` and tests it. `build` then builds again with `push: true`. The GHA layer cache makes the second build a cache hit, so the pushed image has the same layers.
**When:** Default. Avoid a custom "push then test" order: a broken image would reach GHCR, although it would still not be pinned.

### Pattern 5: Every moving reference lives where a bot can see it
**What:** Dependabot reads `uses:` lines, `FROM` lines and compose `image:` lines. Tool images called from inside `run:` steps are invisible to it. Install CI tools through a pinned action or accept a manual bump and note it.
**When:** Choosing how to run `actionlint`.

### Pattern 6: Pin tag plus digest, comment the tag
**What:** `uses: actions/checkout@<40-hex> # v4.x.y`, `FROM nginx:<x.y>-alpine@sha256:…`, `image: cloudflare/cloudflared:<ver>@sha256:…`.
**When:** All third-party references. For an annotated action tag, resolve the peeled commit (`git ls-remote … 'refs/tags/vX^{}'`), not the tag object.

## Interactions That Constrain Order

| Pair | Coupling | Consequence |
|------|----------|-------------|
| IPv6 `listen [::]:80` and `HEALTHCHECK … localhost` | Busybox `wget` on Alpine can resolve `localhost` to `::1`. If nginx stops listening on IPv6, a `localhost` check fails and the container never turns healthy. | Change both together: `HEALTHCHECK` to `127.0.0.1`. The smoke script asserts `healthy` in a run with IPv6 disabled. |
| IPv6 fix and the stock nginx script | `10-listen-on-ipv6-by-default.sh` only edits `conf.d/default.conf`. It runs before envsubst and exits when the file is missing. This Dockerfile removes that file. The script therefore never touches the template. | The concern in CONCERNS.md has the wrong mechanism. A failure can come only from nginx itself on a kernel without IPv6. The `[::]` listener has no consumer (cloudflared reaches `web` over the IPv4 overlay), so remove it rather than make it conditional. |
| CSP and favicon | `default-src 'none'` blocks the favicon request. | CSP carries `img-src 'self'` from day one. The favicon is a file, not a `data:` URI. Style stays `'unsafe-inline'` because a style hash couples `index.html` bytes to `nginx.conf`. |
| Metadata and indexing | The robots decision lives in an HTTP header and a switch per environment. HTML is baked once. | Never add `<meta name="robots">`. Put `canonical`, `og:url` on the production origin. |
| Pin job and compose edits | The pin overwrites the whole compose file on `deploy` with the `main` copy. | Any compose change on `main` (healthcheck, `cloudflared` pin) goes live on the next pin. No separate deploy step exists, and none may be added. |
| Dependabot and the pin line | The compose `web` line carries the tag `sha-unpinned`. Dependabot would try to resolve it. | `ignore: dependency-name: ghcr.io/elfensky/tropaeum-web` in the `docker-compose` entry. Check the first Dependabot run log. |
| Ruleset and pin job | `GITHUB_TOKEN` cannot be a ruleset bypass actor (GitHub App, role, team only). | Use only rules the pin passes: block deletion, block force push. "Restrict updates", "Require PR", "Require status checks" and "Require signed commits" all block the pin. |
| Required checks and path filters | A required check under a path filter stays "pending" and blocks the merge. | `ci.yml` has no `paths` filter. |
| `cloudflared` pin and its healthcheck | An unpinned or newer `cloudflared` changes behaviour with no rollback signal. | Healthcheck first, then the version pin, so the pin lands under the safety net. |

## Suggested Build Order

Each step is one PR. Each is revertible with `git revert` on `main` unless marked otherwise. Each has a check that does not need production.

| # | Step | Depends on | Revert | Verify before merge | Verify after merge |
|---|------|-----------|--------|---------------------|--------------------|
| 1 | PR gate: `ci.yml`, `scripts/smoke.sh` (assertions for today's behaviour only), `actionlint`, `docker compose config -q`. Not yet called by `deploy.yml`. | none | Delete files | The PR runs its own check and passes. A throwaway commit that adds `add_header` in a `location` makes it fail. | Next PR shows the check. |
| 2 | Gate `main`: `deploy.yml` gets `check` and `needs: check`. Add `.planning/**` and `.github/dependabot.yml` to `paths-ignore` so doc commits stop redeploying. | 1 | Remove `needs` | `actionlint` plus a `workflow_dispatch` run on the branch. | The first push to `main` shows `check → build → pin` green and a normal pin commit on `deploy`. |
| 3 | CI supply chain: SHA-pin all `uses:` lines (both workflows). Add `dependabot.yml` with `github-actions` (weekly, grouped, default cooldown). | 1 (so bot PRs are gated) | Revert | CI green with pinned SHAs. | Dependabot log shows the config parsed. The first bot PR runs the PR gate. |
| 4 | Hygiene that touches the build context: `.dockerignore` (allow-list). | 1 | Revert | Smoke passes. A deliberate missing `!site` makes the smoke fail (proves the guard). | none |
| 5 | Pin nginx: `FROM nginx:<x.y>-alpine@sha256:…`. Add `docker` ecosystem to Dependabot. Same step: IPv6 fix (drop `[::]`, `HEALTHCHECK` to `127.0.0.1`). | 1, 3 | Revert | Smoke in default run and in a run with `--sysctl net.ipv6.conf.all.disable_ipv6=1`: both reach `healthy`. | Production tasks turn healthy in the 30 s `monitor` window; rollback is armed. |
| 6 | nginx hardening: `server_tokens off`, CSP with `img-src 'self'`, HSTS scope decision. One commit each, each with its smoke assertion. | 1, 5 | Revert | Smoke asserts the header on `/`, `/robots.txt`, `/nope`. One manual browser check for CSP console errors. | `curl -I https://tropaeum.app/`. |
| 7 | `cloudflared` health signal: `TUNNEL_METRICS`, exec-form `healthcheck`, `start_period`, `update_config.monitor`. Version not yet changed. Smoke adds `tunnel ready --help` against the image named in compose. | 1 | Revert | `docker compose config -q`. Local proof against a quick tunnel (manual, not a CI gate). | Human reads `docker service ps` and container health on the node. Human only. |
| 8 | Pin `cloudflared` to a version and digest. Add `docker-compose` ecosystem to Dependabot with the own-image `ignore`. | 3, 7 | Revert (and `git revert` on `deploy` for speed) | Smoke pulls the pinned image. | Rolling update completes healthy. |
| 9 | Page metadata and `site/` move: description, Open Graph, `canonical`, favicon file, OG image. Dockerfile `COPY site/`. Smoke asserts description present and favicon `200` with an image type. | 4, 6 | Revert | Smoke. Browser check for CSP violations. | Fetch the page through a link-preview tool. |
| 10 | Governance and runbook: ruleset on `deploy` (block deletion and force push; admin role bypass for humans); optional ruleset on `main` (PR plus required check `ci`). README runbook (tunnel secret, node label, Arcane settings, rollback). | 2 and a real pin to prove against | Disable ruleset in the UI (not in git) | Export the ruleset JSON into `.github/rulesets/`. Cannot be dry-run on a personal repo: assume no "Evaluate" mode. | The next real push to `main` completes the pin. If it fails, disable the ruleset first, then diagnose. Human only. |

**Why this order:**
- Step 1 comes first because every later step is judged by it. Steps 5 to 9 each add an assertion to it.
- Step 2 is split from step 1 so the first change to the production path is small and separate from the new test code.
- Step 3 precedes all image-pinning work so bot PRs exist only when the gate exists.
- Step 7 precedes step 8: the version pin changes `cloudflared` behaviour, and only a health signal can roll a bad version back.
- Step 5 carries the IPv6 fix because the nginx pin changes the base the IPv6 reasoning depends on (re-read the entrypoint scripts of the pinned version).
- Step 9 follows step 6 only because the CSP must already allow the favicon; the CSP written in step 6 does, so the order is not strict.
- Step 10 is last because it is the only step that cannot be verified without a real push to `main`, and its revert is not a git action.

## Anti-Patterns to Avoid

### Anti-Pattern 1: A second copy of the checks in `deploy.yml`
**What:** Pasting smoke steps into both workflows.
**Why bad:** The PR proves one thing and `main` runs another.
**Instead:** `workflow_call` of `ci.yml`.

### Anti-Pattern 2: `pull_request_target` or a login step in the PR path
**What:** Giving PR runs a registry token or secrets so they can "test the pushed image".
**Why bad:** Dependabot and fork runs get a read-only token and no secrets. A secret-bearing PR trigger runs untrusted code with credentials.
**Instead:** Build with `load: true` on the runner. Never push from `ci.yml`.

### Anti-Pattern 3: Auto-merging bot PRs
**What:** Dependabot auto-merge on green checks.
**Why bad:** A merge to `main` is a production deploy. Smoke cannot prove tunnel behaviour.
**Instead:** Human merge. Keep Dependabot's default cooldown so brand-new releases wait.

### Anti-Pattern 4: Hoping `GITHUB_TOKEN` can bypass a ruleset
**What:** A "restrict updates" rule on `deploy` plus a bypass entry for the Actions bot.
**Why bad:** The built-in token is not an eligible bypass actor. The pin job fails and production stops updating.
**Instead:** Deletion and force-push rules only. Close the remaining gap (a writer pushing a fast-forward commit) with a GitHub App token and bypass entry only if a second writer appears.

### Anti-Pattern 5: Shell-form healthcheck on `cloudflared`
**What:** `CMD-SHELL` or `curl` in the compose healthcheck.
**Why bad:** The official image is distroless: no shell, no `curl`. The check fails forever and rollback fires on every update.
**Instead:** Exec form: `["CMD", "cloudflared", "tunnel", "--metrics", "127.0.0.1:<port>", "ready"]`.

### Anti-Pattern 6: `add_header` in a new `location` (existing rule, now enforced)
**Instead:** Smoke asserts every header on three paths. A cheap `awk` lint for `add_header` inside `location` may sit beside it.

## Scalability Considerations

Load is not the axis here. The axes are environments and writers.

| Concern | Today (1 env, 1 writer) | 2 environments | Several writers |
|---------|-------------------------|----------------|-----------------|
| Pin job | Hardcoded `ENV_NAME: production` | Parameterise by env; one compose per env | Same |
| Ruleset on `deploy` | Deletion and force-push block | Same | App-token bypass plus "restrict updates" |
| `main` gate | Optional | Required check `ci` | Required check plus review |
| Dependabot | Weekly, grouped | Same | Add reviewers/assignees |
| Smoke | One image, two modes | Same script, compose-driven image ref | Same |

## Open Questions for Phase Research

- Step 5: confirm on the chosen pinned nginx version whether a kernel without IPv6 makes `listen [::]:80` fail at start. The CI runner cannot reproduce `ipv6.disable=1`; removing the listener is the fix that does not depend on the answer.
- Step 7: confirm `cloudflared tunnel ready` flags and the default metrics address inside the current official image. Cloudflare's monitoring page URL returned 404 during this research; the evidence is cloudflared source mirrors (MEDIUM).
- Step 8: Andrei or the operator must read the `cloudflared` image now running in production. A planning session may not touch the live swarm.
- Step 10: confirm the repository owner type and whether "Evaluate" enforcement exists for it.
- Step 6: HSTS `includeSubDomains` and `preload` need a human decision on every current and planned `tropaeum.app` subdomain.

## Sources

- nginx image entrypoint script `10-listen-on-ipv6-by-default.sh` (exits when `default.conf` is missing or `/proc/net/if_inet6` is absent): [docker-nginx](https://raw.githubusercontent.com/nginx/docker-nginx/master/entrypoint/10-listen-on-ipv6-by-default.sh) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4311) (HIGH)
- GitHub rulesets: bypass list limited to roles, teams, GitHub Apps, Dependabot; no mention of `GITHUB_TOKEN`: [Creating rulesets for a repository](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4316) (HIGH for the list, MEDIUM for the conclusion about the Actions bot)
- Community report that the built-in Actions bot cannot be a bypass actor and that GitHub declined to add it: [community discussion 13836](https://github.com/orgs/community/discussions/13836) (MEDIUM)
- Dependabot ecosystems `docker` and `docker-compose` (v2, v3): [Supported ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4130) (HIGH)
- Dependabot options (`directory`, `ignore`/`dependency-name` uses the full repository name for Docker, `groups`, default 3-day `cooldown`): [Options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4127) (HIGH)
- `cloudflared tunnel ready` (added by PR #1135) and `/ready` returning 200 only with active connections: [cloudflared source mirror](https://git.nixnet.services/curben/cloudflared-mirror/src/tag/2025.4.0/metrics/readiness.go), [PR #1135 merge](https://git.nixnet.services/curben/cloudflared-mirror/commit/3480a33fce1421bcd967388511c0d8a6eb8cee28) (MEDIUM; mirror, not the official repo)
- Distroless `cloudflared` image has no shell, so exec-form healthchecks only: [Unraid app notes](https://ca.unraid.net/apps/cloudflare-tunnel-0g72jml1bylz1d) (MEDIUM)
- Repo facts: `.github/workflows/deploy.yml`, `Dockerfile`, `deploy/nginx.conf`, `deploy/production/compose.yaml`, `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/CONCERNS.md` (HIGH)
- Not looked up, from general knowledge (MEDIUM): Dependabot-triggered `pull_request` runs get a read-only token and no repository secrets; Swarm holds a task in "starting" until its healthcheck passes, so start-first waits for health; busybox `wget` and `localhost` resolving to `::1`. The confidence tiers in this file were assigned by hand, not through the `classify-confidence` seam.
