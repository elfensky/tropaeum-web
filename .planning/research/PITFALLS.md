# Pitfalls Research

**Domain:** Maintenance hardening of a static nginx site shipped as a Docker image to a Docker Swarm stack behind a Cloudflare Tunnel, built and pinned by GitHub Actions
**Researched:** 2026-11-02
**Confidence:** HIGH for items marked "verified locally" (run against `nginx:1-alpine` = nginx 1.31.8 and `cloudflare/cloudflared:latest` = 2026.10.7 on 2026-11-02). MEDIUM for GitHub ruleset and Dependabot behavior (community reports plus partial official docs).

## Phase labels used below

The roadmap decides the real phase names. These labels map each pitfall to the likely work package.

| Label | Work package | Source item |
|-------|--------------|-------------|
| P-CI | PR-time CI gate (build, probes, `nginx -t`, compose, actionlint) | 1 |
| P-PIN | SHA-pinned actions, pinned base images, Dependabot | 2, 3 |
| P-TUN | cloudflared health signal | 4 |
| P-HDR | CSP, `server_tokens`, HSTS, IPv6 listener | 5, 8 |
| P-REPO | `.dockerignore`, `deploy` ruleset | 6 |
| P-META | Meta description, Open Graph, favicon | 7 |

Suggested order: P-CI first (every later change then runs through the gate), then P-HDR, P-PIN, P-TUN, P-REPO, P-META. P-HDR and P-META both edit `deploy/nginx.conf` or `index.html`; the P-CI probes are what keep them safe.

## Critical Pitfalls

### Pitfall 1: `.dockerignore` that excludes `deploy/` breaks the build

**What goes wrong:** `CONCERNS.md` proposes a `.dockerignore` that excludes `.git`, `.github`, `deploy`, and `*.md`. The Dockerfile runs `COPY deploy/nginx.conf ...`. Excluding `deploy` removes that file from the build context. The build fails (best case) or a later edit makes it succeed with a wrong file.
**Why it happens:** The "exclude deploy" advice treats `deploy/` as ops-only. Here `deploy/nginx.conf` is an image input and `deploy/production/compose.yaml` is the ops file in the same folder.
**Consequences:** `COPY` fails with "file not found". If `deploy/production` is excluded by a glob but `deploy/nginx.conf` is not, the failure hides until someone moves the file.
**Prevention:** Use an allowlist, not a denylist: `*` then `!index.html` then `!deploy/nginx.conf`. The Dockerfile copies exactly two files, so the context is exactly two files. A new file then needs an explicit `!` line, and a missing one fails loudly at `COPY`.
**Warning signs:** `.dockerignore` contains `deploy` or `deploy/`. The PR build step prints `COPY failed: file not found in build context`.
**Phase:** P-REPO. The P-CI image build is the detector, so P-CI must land first.
**Confidence:** HIGH (Dockerfile read in this repo).

### Pitfall 2: The `ROBOTS_TAG` probe tests the wrong mode and passes for the wrong reason

**What goes wrong:** Three container states exist, not two.
1. Default: image `ENV` applies, so `X-Robots-Tag: noindex, nofollow` and a keep-out `robots.txt`.
2. Production: `ROBOTS_TAG=` (empty), so no header and `robots.txt` answers 404.
3. Unset: `docker run -e ROBOTS_TAG` (no `=`) with `ROBOTS_TAG` unset on the host.

State 3 removes the image default from the container. Verified locally: the container env then has no `ROBOTS_TAG`, the response has no `X-Robots-Tag`, and `/robots.txt` answers 404. The site fails open. The cause is in the template: nginx variable names are case-insensitive, so `set $robots_tag "${ROBOTS_TAG}"` refers to itself when envsubst leaves the token in place, and it evaluates to empty.
**Why it happens:** `-e NAME` and `-e NAME=` look the same in a script. A CI probe for "production mode" that uses the short form passes its "header absent" assertion while testing the unset state. The same trap exists in YAML: `ROBOTS_TAG:` (null) is not `ROBOTS_TAG: ''`.
**Consequences:** A green PR check that does not prove the production path. A future compose edit that makes the value null or drops the line is not caught if the probe has the same blind spot.
**Prevention:**
- Write probes with an explicit `=`: `-e 'ROBOTS_TAG='`.
- In default mode assert the header equals exactly `noindex, nofollow` and the `robots.txt` body is `User-agent: *` plus `Disallow: /`.
- In production mode assert the header is absent and `/robots.txt` is 404.
- Assert the production compose yields an empty string: `docker compose -f deploy/production/compose.yaml config --format json | jq -e '.services.web.environment.ROBOTS_TAG == ""'`.
- Do not "fix" state 3 by guessing. Decide in P-CI whether to make the template fail closed on unset (for example a `map` that treats empty and unset the same is wrong; use a separate explicit `ROBOTS_ALLOW=1`-style switch if the owner wants unset to be closed). Record the decision as a Key Decision.
**Warning signs:** Probe script uses `-e ROBOTS_TAG` without `=`. Probe uses `grep` without `-i` on header names (nginx sends `X-Robots-Tag`, HTTP is case-insensitive, other servers differ). A probe that only checks "no output" for the absent case, so a failed `curl` also passes.
**Phase:** P-CI.
**Confidence:** HIGH (verified locally on nginx 1.31.8).

### Pitfall 3: `add_header` in any new `location` silently strips every server-level header

**What goes wrong:** Verified locally: a `location` that declares its own `add_header` (for example `Cache-Control` on a favicon) loses `X-Robots-Tag`, HSTS, CSP, and all other server-level headers on that path. `nginx -t` passes. The tools that need to be added (CSP, favicon caching, OG image) are exactly the ones that tempt a `location` block.
**Why it happens:** nginx inherits `add_header` only when the child level declares none. The rule lives in a comment in `deploy/nginx.conf`, nowhere else.
**Consequences:** The favicon or `og:image` path is served without `X-Robots-Tag`. In a staging stack this indexes an asset. In production it drops CSP and HSTS on that path.
**Prevention:**
- Use `expires 1h;` (or `expires epoch;`) in a location. Verified: `expires` emits `Cache-Control` and `Expires` and keeps the server-level headers.
- Add the header probe for every location: `/`, `/robots.txt`, each asset path, and a 404 path. Assert the full header set on each. `nginx -t` cannot catch this.
- Keep the 404 path in the probe: server-level headers use `always`, so a 404 must carry them too.
**Warning signs:** A diff to `deploy/nginx.conf` that contains `add_header` indented deeper than two spaces. A header probe that only requests `/`.
**Phase:** P-CI (probe), P-META and P-HDR (the edits that tempt it).
**Confidence:** HIGH (verified locally).

### Pitfall 4: Dropping `listen [::]:80` breaks the image HEALTHCHECK

**What goes wrong:** The usual fix for "no IPv6 on the host" is to delete `listen [::]:80`. The Dockerfile HEALTHCHECK is `wget -qO- http://localhost/`. Verified locally: busybox `wget` resolves `localhost` to `::1` first. With the IPv6 listener removed it prints `Connection refused`, while `http://127.0.0.1/` works. Every task would go unhealthy, and start-first would roll back every deploy.
**Why it happens:** The two changes live in two files (`deploy/nginx.conf`, `Dockerfile`) and two phases of thought.
**Consequences:** A failed rollout, caught only after the pin is live, because the PR build does not wait for health unless P-CI does.
**Prevention:** Change both together: remove the `[::]` listener and set the HEALTHCHECK to `http://127.0.0.1/`. In P-CI, wait for `State.Health.Status == healthy` (poll `docker inspect`) before probing, instead of `sleep`.
**Warning signs:** A PR that touches `deploy/nginx.conf` listen lines but not the Dockerfile HEALTHCHECK.
**Phase:** P-HDR (item 8), gated by P-CI health wait.
**Confidence:** HIGH (verified locally).

### Pitfall 5: The IPv6 concern in `CONCERNS.md` has the wrong mechanism, and a CI test cannot reproduce the real failure

**What goes wrong:** `CONCERNS.md` says the nginx image's `10-listen-on-ipv6-by-default.sh` may leave a `[::]` listener in place. Verified locally: that script only adds a `listen [::]:80;` line to the stock `default.conf` when IPv6 exists, and exits at once when the file is missing. It runs before `20-envsubst-on-templates.sh`, so it never touches the rendered file. The `[::]:80` listener comes only from `deploy/nginx.conf`. The only real failure is a host kernel without IPv6 (for example `ipv6.disable=1` on the kernel command line, so no `/proc/net/if_inet6`). Then nginx exits with `socket() [::]:80 failed (97: Address family not supported by protocol)`.
Verified locally that two common simulations do not reproduce it: `docker run --sysctl net.ipv6.conf.all.disable_ipv6=1` starts nginx without error, and `nginx -t` passes with the `[::]` listener. GitHub-hosted runners have IPv6 in the kernel too.
**Why it happens:** `nginx -t` checks syntax and file access, not socket binding for each address family. A sysctl does not remove the address family.
**Consequences:** A green CI says nothing about this failure. The first signal would be a task that exits on a node with an IPv6-less kernel.
**Prevention:** Choose one of two honest options.
- Remove `[::]:80` (ingress is IPv4 only: cloudflared reaches `web:80` over the IPv4 overlay) and fix the HEALTHCHECK (Pitfall 4). This removes the failure class and needs no test.
- Keep `[::]:80` and add a README node check: `test -f /proc/net/if_inet6` on each `role == apps` node.
Do not write a CI test that claims to cover this.
**Warning signs:** A PR description that says "tested without IPv6" with a sysctl or `nginx -t` as the evidence.
**Phase:** P-HDR. Record the choice as a Key Decision.
**Confidence:** HIGH for the script behavior and the two non-reproductions; MEDIUM for the kernel-level failure message (standard nginx behavior, not reproduced).

### Pitfall 6: cloudflared healthcheck written in shell form, or on an unset metrics address

**What goes wrong:** The official image is distroless (`gcr.io/distroless/base-debian13:nonroot`), has no shell, no `curl`, no `wget`, and no built-in HEALTHCHECK. Verified: `Entrypoint ["cloudflared"]`, `User 65532:65532`, `Healthcheck null`. A healthcheck of the form `CMD-SHELL ...` or a `curl` command always fails, so every task becomes unhealthy and start-first rolls back or never converges.
The working probe is the built-in subcommand `cloudflared tunnel ready`, which calls the metrics server's `/ready` endpoint and sets the exit code (verified in `--help`). It needs a known metrics address. In a container, the default is `0.0.0.0:20241` to `20245`, then a random port, so the probe cannot know which port was chosen.
**Why it happens:** Copying a `wget`/`curl` healthcheck from another service. Not realizing `ready` needs `--metrics`.
**Consequences:** Two failure modes. (a) Exec form is used but the address is unknown, so the probe hits the wrong port, tasks stay unhealthy, and the update rolls back forever. (b) The default metrics listener on `0.0.0.0` is reachable by any other service on the `internal` overlay network.
**Prevention:**
- Set `TUNNEL_METRICS: 127.0.0.1:2000` (or `--metrics`) in the service so the address is fixed and loopback only.
- Use exec form: `test: ["CMD", "cloudflared", "tunnel", "--metrics", "127.0.0.1:2000", "ready"]`.
- Add `start_period: 30s`, `interval: 30s`, `timeout: 5s`, `retries: 3`.
- Set `update_config.monitor` to at least `start_period` plus one interval. The current cloudflared `update_config` has no `monitor`, and Swarm's default monitor window is short, so a late failure falls outside the rollback window. `web` already uses `monitor: 30s`.
- Test the exact `test:` array on a throwaway local container with a real token before pinning it in the stack. A fake token cannot prove readiness.
**Warning signs:** `CMD-SHELL`, `curl`, `wget`, or `/bin/sh` anywhere in the cloudflared healthcheck. Tasks in `starting` forever. `docker service ps` shows a rollback loop after the first deploy of the healthcheck.
**Phase:** P-TUN.
**Confidence:** HIGH for image contents and the `ready` command; MEDIUM for `/ready` returning non-ready until connected (documented behavior of the endpoint, not exercised without a token); MEDIUM for the Swarm `monitor` default.

### Pitfall 7: A healthcheck added together with a version pin cannot be told apart from a bad update

**What goes wrong:** Adding the healthcheck, pinning the version, and moving off `:latest` in one change means a rollback has three possible causes, and the pin job deploys it to production the moment it merges.
**Why it happens:** All three edits touch the same 25 lines of compose.
**Consequences:** A failed rollout with no way to see which change did it. The `cloudflared` service is production ingress, so a loop takes the site down if both replicas roll back badly. (Start-first with two replicas keeps one old task until the new one is healthy, which limits but does not remove the risk.)
**Prevention:** Two commits to `main`, in this order: (1) pin the exact version that is running now (read it from a running task: `cloudflared version`, which is `2026.10.7` for the current `latest`); (2) add the healthcheck and `TUNNEL_METRICS`. Deploy one, observe, then deploy two. Keep the stale compose comment "ENTRYPOINT is already `cloudflared --no-autoupdate`" in mind: the current image sets `ENV NO_AUTOUPDATE=true` and `ENTRYPOINT ["cloudflared"]`, so fix the comment when pinning.
**Warning signs:** One PR that changes `image:`, `healthcheck:`, and `environment:` of `cloudflared`.
**Phase:** P-PIN then P-TUN, in separate pins.
**Confidence:** HIGH (image inspected).

### Pitfall 8: A ruleset that blocks the `GITHUB_TOKEN` pin push, or that quietly fails to protect

**What goes wrong:** The repo `elfensky/tropaeum-web` is a public repo owned by a user account, with no rulesets today (checked with the GitHub API: `[]`). The workflow default token permission is `read`. A ruleset with "Restrict updates" or "Require a pull request" on `deploy` blocks the pin job, because `GITHUB_TOKEN` is not a bypass actor. Community reports (a ruleset issue on a GitHub Actions bot push, closed with a PAT fix) say "GitHub Actions" is not selectable in the bypass dropdown, and that adding it did not help. GitHub's own docs list roles, teams, and apps as bypass actors and do not mention `GITHUB_TOKEN`.
The reverse failure also exists: a ruleset with the repository-admin role in the bypass list lets the owner push to `deploy` by hand, which is the exact thing the ruleset is meant to stop.
**Why it happens:** "CI-only" sounds like "block everyone except the bot". Rulesets can only block everyone, or exempt named roles.
**Consequences:** Either the next deploy fails with `Changes must be made through a pull request` or `Cannot update this protected ref` (visible, but only after a merge to `main` and a built image), or the protection is cosmetic.
**Prevention:**
- Decide the model before writing the ruleset. Option A (recommended, keeps `GITHUB_TOKEN` and the no-loop property): ruleset on `deploy` with "Restrict deletions" and "Block force pushes" only. No "Restrict updates", no PR rule. This stops deletion and history rewrites, and it does not stop a human fast-forward push. Accept that, document it.
- Option B (true CI-only): add a restricting rule and push with a credential that can bypass (a deploy key or a GitHub App token). That replaces `GITHUB_TOKEN`, adds a secret to manage, and changes the "pushes with GITHUB_TOKEN trigger no workflows" safety. Take B only if A is not enough.
- Test with a real pin, not `workflow_dispatch` on an unchanged commit. The pin job's "already pinned" branch returns before any push, so a dispatch of the same SHA proves nothing. Merge a trivial change to `main` and confirm a new `chore(deploy)` commit lands on `deploy`.
- Keep the first-run path in mind: `git switch --orphan deploy` runs only if `deploy` is missing. A "restrict creation" rule would block a recreation after an accidental deletion.
**Warning signs:** Ruleset rules list includes "Restrict updates" or "Require a pull request" while the pin job still uses `GITHUB_TOKEN`. The bypass list is empty or contains only the admin role. A ruleset "evaluate" mode is not available on all plans, so do not rely on a dry run.
**Phase:** P-REPO.
**Confidence:** MEDIUM (community reports, GitHub docs silent on `GITHUB_TOKEN`; repo ownership and empty ruleset list verified via API).

### Pitfall 9: Action SHA pins done wrong (annotated tag SHA, no version comment, or unpinned transitive pieces)

**What goes wrong:** Four recurring mistakes.
1. Copying the SHA shown for an annotated tag. That is the tag object, not the commit. `uses:` needs the commit SHA. Dereference with `git ls-remote https://github.com/<owner>/<repo> 'refs/tags/<tag>^{}'` or `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha`.
2. A pin without the `# vX.Y.Z` comment. Dependabot then updates the SHA and cannot keep the comment current, and reviewers cannot read the version. GitHub changed Dependabot in 2022 to update the semver comment next to a SHA.
3. Pinning the four actions and leaving the rest of the chain floating. `runs-on: ubuntu-latest` floats. `setup-buildx-action` pulls a BuildKit image and `docker/build-push-action` pulls buildx binaries by their own defaults. Any new tool added to the PR job (`actionlint`, `shellcheck`) is also unpinned unless pinned on purpose.
4. Using `bash <(curl .../main/scripts/download-actionlint.bash)` to get `actionlint`. That executes unpinned remote code, which defeats the pins.
**Why it happens:** Pinning looks like a find-and-replace.
**Consequences:** A pin that fails with `unable to find version` (wrong SHA type), or a pin that looks safe and is not.
**Prevention:**
- Pin with a tool that dereferences correctly (`pinact`, or `gh api` as above), then run `zizmor` or `pinact run --check` in P-CI to fail PRs that add an unpinned `uses:`.
- Turn on the repo setting "Require actions to be pinned to a full-length commit SHA" (Settings, Actions, General). A community report says it also applies to nested composite actions, which can break the first run after enabling. Enable it in the same PR that finishes pinning, and read the failures.
- Get `actionlint` as a pinned container (`rhysd/actionlint@sha256:...`) or a release tarball with a checksum check in the workflow.
- Leave `ubuntu-latest` alone unless a runner change causes a failure; note it as accepted drift.
**Warning signs:** `uses: owner/repo@<40 hex>` with no comment. `curl | bash` or `bash <(curl ...)` in any `run:`. The SHA 404s in the Actions log.
**Phase:** P-PIN (pins), P-CI (the check that keeps them).
**Confidence:** HIGH for annotated-tag behavior and the comment update; MEDIUM for the repo-level policy details (community write-ups, no official page read).

### Pitfall 10: Dependabot config that proposes nonsense, auto-deploys, or misses the Dockerfile

**What goes wrong:**
- `package-ecosystem: docker` reads Dockerfiles only. Compose files need `docker-compose` (the supported-ecosystems table lists Docker Compose v2 and v3 as its own entry). Without both entries, `cloudflared` in `deploy/production/compose.yaml` is never updated.
- Dependabot also reads `image: ghcr.io/elfensky/tropaeum-web:sha-unpinned` in the compose file. The tag is not a version. Expect either noise or an attempted odd bump. Add an `ignore` entry for `ghcr.io/elfensky/tropaeum-web`.
- A merged Dependabot PR is a push to `main`. That runs build and pin and ships to production with no extra human step. A bump of `nginx` or `cloudflared` therefore deploys itself at merge time.
- Dependabot PRs run workflows with a read-only `GITHUB_TOKEN` and without the repo's Actions secrets. A PR job that logs in to GHCR, or pushes, fails on Dependabot PRs only.
- Version bumps for base images that float (`nginx:1-alpine`) never produce a PR, because the tag does not change; only the digest changes. A digest-only pin (`nginx:1-alpine@sha256:...`) needs the tag kept next to the digest so the bot can move both.
**Why it happens:** A copy of a generic `dependabot.yml` with only `github-actions`.
**Consequences:** Pins that go stale unseen, or Dependabot PRs that cannot pass CI, or an unattended tunnel upgrade in production.
**Prevention:**
- Three `updates` entries: `github-actions` (`/`), `docker` (`/`), `docker-compose` (`/deploy/production`). Weekly schedule. A `cooldown` of several days for `docker` and `docker-compose` (the options reference says Dependabot applies a 3-day default cooldown to version updates, supported for these ecosystems; set it explicitly so it is visible).
- No auto-merge for `nginx` and `cloudflared`. Merge by hand after the PR build and probes are green.
- The PR job uses `pull_request`, never `pull_request_target`; no GHCR login; `push: false`; `load: true`.
- Pin as `nginx:<minor>-alpine@sha256:<index digest>` (the multi-arch index digest, not an arch digest) and `cloudflare/cloudflared:<calver>@sha256:...`. Keep the compose `image:` line for the app in the plain form the pin job needs.
- Confirm the first Dependabot run opens the expected PRs and none for `tropaeum-web`.
**Warning signs:** `.github/dependabot.yml` lists only `github-actions`. A Dependabot PR for the app image. A red PR check on Dependabot PRs that is green on human PRs.
**Phase:** P-PIN, with P-CI's PR job built to work for Dependabot.
**Confidence:** MEDIUM (ecosystem list and cooldown from official docs; digest-and-tag co-update and read-only token behavior from general Dependabot behavior, not re-verified here).

### Pitfall 11: Required status checks that never report (path filters on the PR workflow)

**What goes wrong:** A PR workflow with `paths:` or `paths-ignore:` does not run for some PRs. If its job name is later made a required check, those PRs wait forever for a status that never arrives. The deploy workflow already has `paths-ignore: '*.md'`, and copying its `on:` block into the PR workflow carries this trap.
**Why it happens:** The deploy workflow's filter is correct for a deploy. A copy for CI is not.
**Consequences:** Blocked PRs, then a "temporary" removal of the required check, then no gate.
**Prevention:** The PR workflow has no path filter. It runs on every `pull_request`. Keep it small enough to take a few minutes. Give it its own file (`.github/workflows/ci.yml`), its own `permissions: contents: read`, and its own concurrency group with `cancel-in-progress: true` (the deploy group keeps `false`, which must not be copied).
**Warning signs:** `paths-ignore` in `ci.yml`. A PR that only edits a README and shows no checks.
**Phase:** P-CI.
**Confidence:** HIGH (standard GitHub Actions behavior).

### Pitfall 12: PR probes that race the container, or that cannot fail

**What goes wrong:** `docker run -d` then `curl` immediately races nginx startup. `sleep 5` is a flaky wait. A probe written as `curl ... | grep -qi header` under `set -e` without `pipefail` passes when `curl` fails. A probe for "header absent" passes when the server is down.
**Prevention:**
- Poll health: loop on `docker inspect -f '{{.State.Health.Status}}'` until `healthy`, with a timeout, then fail with `docker logs`.
- Use `curl -sS --fail -D headers.txt -o body.txt` and then assert on `headers.txt`, so a connection error stops the script. Use `set -euo pipefail`.
- For "absent", first assert HTTP 200 on `/` in the same run, then assert no match.
- Run `nginx -t` through the entrypoint: `docker run --rm -e ROBOTS_TAG= <image> nginx -t`. Verified: the entrypoint renders the template for a command that starts with `nginx`, so `-t` tests the rendered file for the current mode. `nginx -t` run via `--entrypoint` skips rendering and tests a missing or stale file.
- Test both modes against the same image tag the pin job would push, built with `load: true`.
**Warning signs:** `sleep` in the probe step. A probe step that exits 0 when the container is stopped.
**Phase:** P-CI.
**Confidence:** HIGH.

### Pitfall 13: `docker compose config -q` gives false comfort on a Swarm file

**What goes wrong:** `docker compose config` validates Compose schema. It ignores Swarm-only semantics (`placement.preferences`, `update_config.order`, `rollback_config`), and external secrets pass without the secret existing. It cannot tell that the `image:` line still matches the pin job's `grep`.
**Prevention:**
- Run `docker compose -f deploy/production/compose.yaml config -q` for schema, and add two explicit assertions: (a) the pin job's regex still matches `image: ghcr.io/${repo}:` with no trailing comment (copy the exact `grep -qE` from the workflow, or run the pin step's render logic against the file with a dummy SHA); (b) `ROBOTS_TAG` is the empty string (Pitfall 2).
- Where the runner's Docker has `docker stack config`, use it too. It runs without a Swarm.
- Name the limit in the README: placement labels, the secret, and the Zero Trust hostnames are not checked.
**Warning signs:** The PR job passes after someone adds a trailing comment to the `image:` line, and the pin job then fails on `main`.
**Phase:** P-CI.
**Confidence:** MEDIUM (compose behavior from tool knowledge; `docker stack config` availability depends on the runner's Docker version, check when writing the step).

### Pitfall 14: CSP that blocks its own favicon, or that breaks on a CSS edit

**What goes wrong:**
- `default-src 'none'` also blocks images. A favicon link loads under `img-src`. With the `CONCERNS.md` policy, `<link rel="icon" href="/favicon.svg">` is blocked in the console, and a `data:` favicon needs `img-src data:`. Browsers also request `/favicon.ico` on their own.
- `base-uri`, `form-action`, and `frame-ancestors` do not fall back to `default-src`. Each needs its own directive or stays open.
- A hash-based `style-src 'sha256-...'` is tighter than `'unsafe-inline'` but breaks the page styling on any whitespace edit to the `<style>` block. Nothing fails in CI.
- Cloudflare features that inject script or markup into proxied HTML (Web Analytics auto-injection, Email Address Obfuscation, Rocket Loader, if enabled on the zone) are blocked by the CSP and also contradict the "no scripts, no third-party requests" promise. This is a zone setting outside the repo.
- `Content-Security-Policy-Report-Only` first is not useful here: there is no reporting endpoint and no script to collect violations.
**Prevention:**
- Policy: `default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'self'`. Add `data:` to `img-src` only if the favicon is inline.
- Keep `'unsafe-inline'` for styles on a page with no scripts, or add a CI step that recomputes the style hash and compares it to the header.
- Verify in a real browser once (chrome-devtools: load the page, read the console for CSP violations) after the favicon and OG work, and once against the public hostname.
- After each deploy, `curl -s https://tropaeum.app/ | grep -c '<script'` must print `0`.
- Place the header at server level with `always` (Pitfall 3). Verified: the policy string with single quotes and semicolons passes inside a double-quoted `add_header` and `envsubst`.
**Warning signs:** A CSP violation in the console on first load. The page looks unstyled after a CSS edit. A `<script>` in the public HTML that is not in `index.html`.
**Phase:** P-HDR, re-checked in P-META.
**Confidence:** HIGH for CSP fallback rules and the header placement; MEDIUM for which Cloudflare features are on (zone state unknown).

### Pitfall 15: HSTS `preload` is redundant here, and `includeSubDomains` has a long tail

**What goes wrong:** `.app` is on the browser HSTS preload list as a whole top-level domain (Google Registry, launched 2018; secondary sources, not re-checked against the list). Browsers that use the list already force HTTPS for `tropaeum.app` and every subdomain. The `preload` token adds nothing, and submitting `tropaeum.app` for individual preloading is pointless. The header's real effect is for browsers and clients outside that list. On plain HTTP the header is ignored (the origin sends it on port 80 behind the tunnel; the edge terminates TLS, so this is harmless).
If the token stays, the hstspreload.org requirements are strict and the policy says removal takes months and is hard to undo.
Other HSTS mistakes:
- Cloudflare's own HSTS setting (SSL/TLS, Edge Certificates) can add a second `Strict-Transport-Security` header. Two headers with different values are valid HTTP but confusing.
- A `max-age` jump from none to one year with no ramp makes a mistake last a year for returning visitors.
**Prevention:**
- Drop `preload` from the header. Keep `includeSubDomains` only after listing every DNS record under `tropaeum.app` in the Cloudflare zone (a human check, not in the repo). Because `.app` already forces HTTPS, this is a low-risk confirmation, not a blocker.
- Check the public header: `curl -sI https://tropaeum.app/ | grep -ci '^strict-transport-security'` must print `1`.
- Ramp `max-age` (for example 300, then 86400, then 31536000) only if the owner wants a safety margin. With the `.app` preload this adds little.
- Do not submit to hstspreload.org. Record that in Key Decisions.
**Warning signs:** `preload` still in the header after the "scope confirmed" task is marked done. Two HSTS headers on the public URL.
**Phase:** P-HDR.
**Confidence:** MEDIUM (`.app` preload from secondary sources; hstspreload.org requirements read directly).

## Moderate Pitfalls

### Pitfall 16: `server_tokens off` is checked on the wrong URL

**What goes wrong:** `server_tokens off;` hides the version only. The header still reads `Server: nginx`. Cloudflare replaces or hides the `Server` header on the public URL, so a check against `https://tropaeum.app` proves nothing. Verified locally: with the directive set, the origin answers `Server: nginx`.
**Prevention:** Assert `Server: nginx` with no digits in the P-CI origin probe. Put the directive in the `server` block (it is valid there, verified). Do not claim an `Server`-header removal; that needs a third-party module.
**Phase:** P-HDR and P-CI.
**Confidence:** HIGH (verified locally).

### Pitfall 17: `og:image` that scrapers ignore, and a favicon that is a 404

**What goes wrong:**
- `og:image` must be an absolute `https://` URL. Link previews (Facebook, Slack, Discord, iMessage, X) use PNG or JPEG, commonly 1200 by 630. SVG is not reliably accepted.
- Without a `<link rel="icon">`, browsers request `/favicon.ico`. It 404s today and adds log noise. A new icon file needs a MIME type and the headers from Pitfall 3.
- `og:url` and `<link rel="canonical">` must name one host. Both `tropaeum.app` and `www.tropaeum.app` serve the same page. Pick the apex for the canonical, and redirect `www` in Cloudflare (outside the repo).
- A `<meta name="robots">` in `index.html` would override the fail-closed design in one direction or the other. Leave indexing control to the header and `robots.txt`.
- The meta description appears in search results only after indexing. Production is indexable (`ROBOTS_TAG: ''`), so keep it accurate and short (under about 160 characters).
- A new binary asset (the OG image) increases image size slightly and is the first request path that is not `/` or `/robots.txt`. It must pass the full-header probe.
**Prevention:** Add the asset paths to the P-CI probe list. Test link previews after deploy with the public URL (the scrapers cache aggressively, so get the image right first). Keep `og:image` in the same repo as a file, not an external URL (the privacy promise).
**Warning signs:** `og:image` with a relative URL. A 404 on `/favicon.ico` in the nginx log after the work is done.
**Phase:** P-META.
**Confidence:** MEDIUM (platform behavior is common knowledge, not re-fetched).

### Pitfall 18: Base image pin by tag alone, or by digest alone

**What goes wrong:** Pinning `nginx:1-alpine` to `nginx:1.31-alpine` still floats within the minor. A bare digest cannot be read or compared by a person, and loses the tag the bot needs. A digest of one architecture breaks a future multi-arch build. A pinned `nginx` stops receiving Alpine and OpenSSL fixes until the bot moves it, so the bot must be live before the pin.
**Prevention:** `FROM nginx:1.31-alpine@sha256:<index digest>` and `image: cloudflare/cloudflared:2026.10.7@sha256:<index digest>`. Order the work: Dependabot config in the same PR as the pins. Take the digest from `docker buildx imagetools inspect <tag>`. Cloudflare supports a limited window of `cloudflared` versions, so an unmaintained pin will eventually fall out of support.
**Phase:** P-PIN.
**Confidence:** MEDIUM.

### Pitfall 19: `actionlint` finds nothing because the shell checker is missing, or fails on `${{ }}` style

**What goes wrong:** `actionlint` runs `shellcheck` on `run:` blocks only if `shellcheck` is on the path. The pin job's big shell blocks are the place bugs live. On `ubuntu-latest` `shellcheck` is preinstalled, but a container run of `actionlint` may not see it.
**Prevention:** Check the first CI run prints shellcheck findings for a deliberately bad line, then remove the line. Pin the `actionlint` version (Pitfall 9).
**Phase:** P-CI.
**Confidence:** MEDIUM.

### Pitfall 20: PR build cache and secrets leak into the PR path

**What goes wrong:** Copying `cache-to: type=gha,mode=max` into the PR job writes PR caches into the shared 10 GB GitHub cache quota and can evict the `main` cache. Copying `docker/login-action` makes the job fail for Dependabot and fork PRs.
**Prevention:** PR job: `cache-from: type=gha`, no `cache-to` (or a separate `scope`), no login, no `push`.
**Phase:** P-CI.
**Confidence:** MEDIUM.

## Minor Pitfalls

### Pitfall 21: README runbook drift

**What goes wrong:** The runbook (tunnel secret create and rotate, node label, Arcane Git Sync settings) is written once and goes stale. It also must not contain the token or the secret's value.
**Prevention:** Put exact commands with placeholders only. Add a "last verified" date line. Never paste the tunnel token (it belongs in 1Password and the Swarm secret).
**Phase:** P-REPO.

### Pitfall 22: `.dockerignore` and the build-arg `COMMIT_SHA`

**What goes wrong:** Excluding `.git` is correct, because the commit SHA arrives as a build arg (`COMMIT_SHA=${{ github.sha }}`), not from the git directory. Nothing in the Dockerfile reads `.git`. Confirm this stays true if someone adds a `git describe` step.
**Phase:** P-REPO.

### Pitfall 23: gzip settings tested on a page below `gzip_min_length`

**What goes wrong:** `gzip_min_length 1024` means the tiny page is never compressed. A probe that asserts `Content-Encoding: gzip` on `/` fails. Do not add that assertion.
**Phase:** P-CI.

## Phase-Specific Warnings

| Phase topic | Likely pitfall | Mitigation |
|-------------|----------------|------------|
| P-CI: probes | `-e ROBOTS_TAG` without `=` tests an unset state (P2); probes only hit `/` (P3); race on startup (P12) | Explicit `=`, probe every location and 404, poll health |
| P-CI: workflow | Path filter on a required check (P11); GHCR login on PRs (P10, P20) | Own `ci.yml`, no filters, read-only token, no push |
| P-CI: compose | `config -q` passes a broken pin line (P13) | Run the pin job's regex and a `ROBOTS_TAG == ""` assertion |
| P-PIN: actions | Annotated-tag SHA, missing comment, unpinned `actionlint` download (P9) | `pinact`/`gh api`, `# vX.Y.Z` comments, pinned `actionlint`, repo SHA policy |
| P-PIN: images | Tag-only or digest-only pins; no bot (P18) | Tag plus index digest, Dependabot in the same PR |
| P-PIN: bot | Missing `docker-compose` entry; app image noise; auto-deploy on merge (P10) | Three entries, `ignore` the app image, no auto-merge for nginx and cloudflared |
| P-TUN: health | Shell-form check; unknown metrics port; short `monitor` (P6); bundled with the version pin (P7) | `TUNNEL_METRICS` on loopback, exec-form `ready`, two separate pins |
| P-HDR: CSP | Blocks favicon; hash breaks on CSS edit; Cloudflare injection (P14) | `img-src 'self'`, `unsafe-inline` for style, public-URL `<script` count |
| P-HDR: HSTS | `preload` is redundant under `.app`; double header at the edge (P15) | Drop `preload`, count headers on the public URL |
| P-HDR: IPv6 | Wrong mechanism blamed; no CI test can reproduce (P5); HEALTHCHECK breaks (P4) | Remove `[::]:80` and change HEALTHCHECK to `127.0.0.1` together |
| P-REPO: ignore | `deploy` excluded (P1) | Allowlist `*`, `!index.html`, `!deploy/nginx.conf` |
| P-REPO: ruleset | Blocks `GITHUB_TOKEN` or protects nothing (P8) | Deletion and force-push rules only, test with a real pin |
| P-META | `location` with `add_header` for assets (P3); relative `og:image`; favicon blocked by CSP (P14, P17) | `expires`, absolute URL, probe the asset paths |

## Items for a human or later research

- Whether the Cloudflare zone has Web Analytics, Email Obfuscation, or Rocket Loader on (Pitfall 14). Zone settings are outside the repo.
- The DNS record list for `tropaeum.app` before keeping `includeSubDomains` (Pitfall 15).
- Whether any `role == apps` node has a kernel without IPv6, if `[::]:80` is kept (Pitfall 5).
- Whether `docker stack config` exists on the GitHub runner's Docker (Pitfall 13).
- The exact GitHub plan limits for ruleset "evaluate" mode on a personal repo (Pitfall 8).

## Sources

- Local verification, 2026-11-02, Docker 29.9.2 on macOS: `nginx:1-alpine` (nginx 1.31.8) with the repo's `deploy/nginx.conf` as a template. Checked the IPv6 entrypoint script text, `nginx -t`, `--sysctl disable_ipv6`, `-e ROBOTS_TAG` versus `-e ROBOTS_TAG=`, `add_header` versus `expires` in a location, `server_tokens off`, and `wget localhost` without an IPv6 listener. (HIGH)
- Local inspection of `cloudflare/cloudflared:latest` (2026.10.7): entrypoint, user, env, healthcheck, `tunnel ready --help`. (HIGH)
- [cloudflared Dockerfile](https://raw.githubusercontent.com/cloudflare/cloudflared/master/Dockerfile) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4319) (HIGH)
- [Cloudflare Tunnel metrics docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/monitor-tunnels/metrics/) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4339): container default metrics bind `0.0.0.0:20241-20245`. The page does not document `/ready` or `tunnel ready`; that comes from the local `--help`. (HIGH for the bind, MEDIUM for `/ready`)
- [HSTS preload requirements](https://hstspreload.org/) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4313) (HIGH)
- [GitHub about rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4297): bypass actors are roles, teams, and apps; `GITHUB_TOKEN` is not mentioned. (MEDIUM)
- [Ruleset bypass issue: GitHub Actions not selectable, PAT fix](https://github.com/hossain-khan/social-sync/issues/31) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4362) (LOW to MEDIUM, single community report)
- [Rulesets governance guide](https://www.stephane-robert.info/en/docs/github-actions/governance/rulesets/) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4361) (LOW)
- [Dependabot options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4127): `cooldown`, `directories`, `groups`. The page was read only for its first 100000 characters. (MEDIUM)
- [Dependabot supported ecosystems](https://docs.github.com/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories): Docker and Docker Compose are separate entries. (HIGH)
- [Dependabot updates SHA-pin version comments (GitHub changelog, 2022-10-31)](https://github.blog/changelog/2022-10-31-dependabot-now-updates-comments-in-github-actions-workflows-referencing-action-versions/) (HIGH)
- [Semgrep: SHA pinning for GitHub Actions org-wide](https://semgrep.dev/blog/2026/sha-pinning-for-github-actions-org-wide): repo and org policy, nested pinning. (LOW to MEDIUM)
- [.app TLD HSTS preload (secondary coverage)](https://www.thesslstore.com/blog/google-launches-dot-app/) (MEDIUM; the preload list itself was not read)
- Project files read: `.planning/PROJECT.md`, `.planning/codebase/CONCERNS.md`, `deploy/nginx.conf`, `Dockerfile`, `deploy/production/compose.yaml`, `.github/workflows/deploy.yml`, `index.html`. GitHub API read-only calls on `elfensky/tropaeum-web`: owner type `User`, public, rulesets `[]`, workflow default permission `read`.
