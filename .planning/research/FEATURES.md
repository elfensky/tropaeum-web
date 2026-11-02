# Feature Research

**Domain:** Maintenance and delivery hardening for a one-page static coming-soon site (nginx image, Docker Swarm, Cloudflare Tunnel, GitHub Actions pin pipeline)
**Researched:** 2026-11-02
**Confidence:** MEDIUM (repo facts HIGH; Dependabot/compose coverage, `cloudflared tunnel ready` and ruleset bypass details MEDIUM, verify in phase)

Scope note: "users" here are three people. Visitors (page loads, link previews, search), the operator (Andrei: safe deploys, fast rollback, detect outages) and the repo itself (supply chain). The Tropaeum app, accounts, mailing list and sign-up form are out of scope (see Anti-Features).

## Feature Landscape

### Table Stakes (Users Expect These)

Missing these = the pinned, revertible pipeline is not trustworthy, or the live page is visibly incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| PR-time CI: image build + `docker run` probes in BOTH indexing modes | The indexing switch and header inheritance are the two fragile areas; today only a human running commands catches a break. PR #1 already defined the checks. | MEDIUM | One script (e.g. `test/smoke.sh`), called from a `pull_request` workflow. Default mode: `/` is 200, `X-Robots-Tag: noindex, nofollow`, `/robots.txt` body has `Disallow: /`. Production mode (`-e ROBOTS_TAG=`): no `X-Robots-Tag`, `/robots.txt` is 404. Both modes: HSTS, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` (and CSP once added) present on `/`, `/robots.txt` AND a 404 path. That last probe is the regression guard for the "no `add_header` in a `location`" rule. Wait for the container to report `healthy` before probing. |
| `nginx -t` on the rendered config | A broken config otherwise reaches `deploy` after push. | LOW | `docker run --rm <image> nginx -t`. The entrypoint renders the envsubst template first because the command starts with `nginx`. Run it for both `ROBOTS_TAG` values. |
| Compose validation | A bad stack file fails late, in Arcane, in production. | LOW | `docker compose -f deploy/production/compose.yaml config -q`. Catches schema and syntax, not Swarm semantics. State that limit in a comment (`shortcut:`). |
| `actionlint` on workflows | A workflow typo blocks deploys with a late failure; actionlint also runs shellcheck on `run:` blocks. | LOW | Pin the actionlint version. First run may flag existing `run:` blocks (quoting); fix them in the same change. It does not check SHA pinning. |
| PR workflow has `permissions: contents: read`, no push, no secrets | PR code (including Dependabot PRs) must not hold write tokens. | LOW | Build with `load: true`, never `push: true`. Do not path-filter the PR workflow if it later becomes a required check (a skipped required check stays pending). |
| GitHub Actions pinned to full commit SHAs, version in a trailing comment | The `build` and `pin` jobs hold `packages: write` and `contents: write`; a moved tag runs attacker code with them. | LOW | Convert once by hand or with a tool (pinact, ratchet), `uses: org/action@<sha> # v4.1.1`. Pin first-party (`actions/checkout`) too, for one rule. |
| Dependabot `github-actions` ecosystem | A SHA pin that is never updated becomes a stale pin and gets ignored. Dependabot keeps the SHA format and rewrites the version comment. | LOW | `.github/dependabot.yml`, weekly. Group updates to cut PR noise. Consider `cooldown` (delay brand-new releases) as cheap supply-chain protection. |
| Base images pinned: `nginx` to a specific version (+ digest), `cloudflared` to a version | `nginx:1-alpine` and `cloudflared:latest` make a rebuild or task restart non-reproducible, so a `git revert` does not restore prior behaviour. | LOW | Form `nginx:<x.y.z>-alpine@sha256:...`. `cloudflared` uses calendar versions (`YYYY.M.P`). Never write a trailing comment on the app `image:` line (pin job `sed`); comments on other lines are fine. |
| Dependabot `docker` (+ `docker-compose`) ecosystems for base images | Same reason as Actions. Pins without a bot rot. | MEDIUM | `docker` for `/Dockerfile`. `docker-compose` for `/deploy/production`: coverage of the filename `compose.yaml` is UNCONFIRMED in docs, so test with a real run and fall back to a manual bump step in the runbook if it does not pick the file up. REQUIRED `ignore` for `ghcr.io/elfensky/tropaeum-web`: its `sha-<commit>` tag is not semver and the pin job owns that line. |
| `cloudflared` health signal | Swarm sees only an image or compose `healthcheck`. Official `cloudflared` has none, so a dead tunnel is "running", and `failure_action: rollback` cannot fire on a bad bump. | MEDIUM | Official image is distroless (no shell, `ENTRYPOINT ["cloudflared"]`, user nonroot), so a shell-form check fails. Use exec form in compose: `test: ["CMD", "cloudflared", "tunnel", "--metrics", "127.0.0.1:60123", "ready"]`, with the same address on the run command or `TUNNEL_METRICS`, plus `interval`, `retries`, `start_period`. `ready` returns success only while connected to the edge (MEDIUM: seen in community images and the upstream mirror, not in Cloudflare's monitoring page). Verify the subcommand exists in the pinned version before relying on it. |
| `server_tokens off` | Standard nginx hygiene, one line. | LOW | Benefit is small: Cloudflare already rewrites the public `Server` header. Do it anyway; it also hides the version in the internal overlay. |
| Content-Security-Policy | The page has no scripts, so a strict policy costs nothing and is a second line of defence. | LOW | Start from `default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'self'`. Add `img-src data:` only if the favicon is an inline data URI. `'unsafe-inline'` for style is acceptable here. Assert the header in the smoke script. |
| HSTS scope decision | `includeSubDomains; preload` for a year commits every present and future `*.tropaeum.app` host to HTTPS, and `preload` does nothing until submitted. | LOW | Code change is a one-liner; the real work is a decision. Recommended: drop `preload` (no submission planned), keep `includeSubDomains` only after confirming every subdomain is proxied by Cloudflare over HTTPS. Browsers ignore HSTS on HTTP, so the header on port 80 is harmless; document it, do not code around it. |
| `.dockerignore` | Context sends `.git`, `.github`, `.planning`, `deploy/` for no reason. | LOW | Use an allow-list: ignore everything, then `!index.html` and `!deploy/nginx.conf`. A naive `deploy` entry (as CONCERNS.md suggests) BREAKS the build, because the Dockerfile copies `deploy/nginx.conf`. The PR build catches this. |
| Ruleset on `deploy`: block deletion and force-push | Cheap, enforceable protection of the rollback surface. | LOW | Works with the existing `GITHUB_TOKEN` push (CI pushes plain fast-forward commits). Public repo, so rulesets are free. |
| README runbook | A recovery path that exists only in one head is not a recovery path. | LOW | Sections: secret create and rotate (Swarm secrets are immutable, so rotation means a new secret name or a remove-and-recreate), node label (`role=apps`), Arcane Git Sync settings (branch, path, poll interval; values come from Andrei, not the repo), rollback, how to tell the tunnel is dead, header verification with `curl -I`, repo-rename edit list. Write the end state, no secret values. |
| Page metadata: `<meta name="description">`, Open Graph text tags, canonical, favicon | Production is indexable and the app promises Discord sharing. A bare `<title>` gives a poor search snippet and a bare link preview. | LOW | `description` (about 150 chars), `og:title`, `og:description`, `og:type=website`, `og:url` and `<link rel="canonical">` (absolute `https://tropaeum.app/`), `og:site_name`, `twitter:card=summary`, `theme-color` per colour scheme. Favicon as an inline SVG data URI in `<link rel="icon">` costs no extra request, and with a declared icon browsers skip `/favicon.ico` (needs `img-src data:` in CSP; MEDIUM, check in a real browser). |
| IPv6 listen fix | If the host kernel has no IPv6, `listen [::]:80` makes nginx exit with `socket() [::]:80 failed (97)`. | LOW | The image's `10-listen-on-ipv6-by-default.sh` edits only `/etc/nginx/conf.d/default.conf`, exits 0 when the file is missing (this Dockerfile deletes it), and runs before the envsubst step, so it never touches the template (HIGH, script read from upstream). Production Swarm hosts probably have IPv6, so the failure is unconfirmed. Cloudflare Tunnel reaches `web` over the IPv4 overlay, so `[::]` buys nothing: delete the `listen [::]:80` line. A CI test is not worth building: a GitHub runner has IPv6 and cannot reproduce the failure (errno 97 needs a kernel without IPv6; `disable_ipv6=1` sysctl still allows the bind). |

### Differentiators (Competitive Advantage)

Not required for a trustworthy pipeline, but they raise confidence cheaply. Core Value (PROJECT.md): "stays up and trustworthy; changes reach production only through the pinned, revertible pipeline".

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Smoke gate before the pin on `main` | Today the pin can point at an image that starts but serves wrong headers. Running the same `test/smoke.sh` on the pushed `sha-` image before `pin` makes a bad build fail before Arcane sees it. | MEDIUM | New job between `build` and `pin` (`pin` needs it); pull the exact pushed tag so the tested bytes are the deployed bytes. Reuse the PR script, never fork it. |
| Required status check on `main` (ruleset) | Makes the PR checks binding, so Dependabot bumps cannot merge red. | LOW | Only useful if Andrei works through PRs (he did for PR #1). Job names become part of the contract. |
| Pin app image by digest in the pin step | `sha-` tags in GHCR are mutable; a digest makes `git revert` restore the exact bytes. | MEDIUM | Touches the `grep`/`sed` pin job (CONCERNS #2, mutable tags). Not in the eight listed items; decide separately. |
| CI-only `deploy` enforcement (restrict updates) | Turns the "CI is the only writer" convention into a rule. | HIGH | `GITHUB_TOKEN` (`github-actions[bot]`) cannot be a ruleset bypass actor; the working pattern is a GitHub App (or deploy key) token with `persist-credentials: false` on checkout (community sources, MEDIUM). Also blocks the human `git revert` rollback in the README unless the owner keeps an admin bypass. Defer until the cheap ruleset has proven too weak. |
| Repo setting "require actions pinned to full SHA" | Makes an unpinned `uses:` fail the run instead of relying on review. | LOW | One-time repo setting, no code. Confirm availability on the account first (MEDIUM). |
| `zizmor` (or similar) workflow audit | Finds template injection and over-broad permissions that `actionlint` does not. | LOW | Run alongside `actionlint`; make it non-blocking at first. |
| `persist-credentials: false` on checkout in `build` and PR jobs | Stops the token living in `.git/config` during steps that do not push. | LOW | The `pin` job keeps credentials because it pushes. |
| `og:image` (1200x630 PNG, same origin) | Link previews in Discord and chat are the main way a trophy-hunting audience first meets the page. Text-only previews look unfinished. | MEDIUM | One extra file plus `COPY`, `.dockerignore` allow-list entry, `og:image` absolute URL, width/height/alt tags. Needs a designed asset, which is the real cost. Crawlers fetch it, so CSP does not apply. |
| `Cross-Origin-Opener-Policy` / `Cross-Origin-Resource-Policy` | Raises external scanner scores. | LOW | Server-level `add_header ... always`; covered by the same header probe. No behavioural risk on a script-free single page. |
| Static privacy guard in CI | Enforces the "no scripts, no external requests" promise at PR time. | LOW | `grep` that `index.html` has no `<script` and no `src=`/`href=` pointing off-site except the lav.ren link. CSP `default-src 'none'` already enforces this in browsers; the grep gives an earlier, plainer failure. |
| Documented external uptime check | Detects a dead public hostname that no in-cluster check sees (Cloudflare tunnel status does not prove origin reachability). | LOW | A runbook line pointing at an existing external monitor. Do not build monitoring in this repo. |
| Dependabot `cooldown` and grouping | Fewer, later, calmer PRs. | LOW | Config only. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| The Tropaeum app, trophy tracking, PSN/Xbox/Steam integration, Discord sharing, purchases | The page announces them | A separate product; belongs in another repo with its own delivery pipeline | Keep the page text only |
| Accounts, backend, database, mailing list, waitlist or sign-up form | Standard on coming-soon pages | Needs a processor, consent, storage and a backend; none exists and the tracker asks for none | None; revisit only as a new, separate decision |
| Analytics, tracking pixels, cookie banner, third-party fonts or embeds | Traffic numbers for a coming-soon page | Breaks the "no scripts, no external requests, no tracking" promise and the CSP; a banner is only needed if cookies exist | Read Cloudflare edge request counts if numbers are wanted |
| `<meta name="robots">` in `index.html` | Looks like normal SEO | Duplicates the `ROBOTS_TAG` switch and breaks the single fail-closed source | Keep the `X-Robots-Tag` header and `robots.txt` as the only indexing controls |
| JSON-LD structured data | SEO guides recommend it | Needs a `<script>` tag, contradicting "script-free" and CSP | Plain `description` and Open Graph tags |
| `sitemap.xml` | Standard for indexable sites | One URL; crawlers find it from the apex link | Skip |
| Hash-based or nonce-based CSP with CI-generated hashes | Removes `'unsafe-inline'` | Any CSS edit changes the hash; needs build machinery that the repo deliberately lacks | `style-src 'unsafe-inline'` with `default-src 'none'` |
| Conditional HSTS only on HTTPS, or `preload` list submission | "Correct" HSTS | Browsers already ignore HSTS on HTTP; preload is hard to undo and needs every subdomain proven | Drop `preload`, confirm subdomains, document |
| Auto-merge of Dependabot PRs | Less toil | Merge to `main` deploys to production, so a green-but-wrong base image bump goes live unattended | Manual merge after green PR checks |
| Blocking vulnerability-scan gate (Trivy/Scout) on the image | Supply-chain checkbox | Fails on upstream nginx CVEs the repo cannot fix; gate noise trains people to ignore it | Let Dependabot bumps carry upstream fixes; optional non-blocking report |
| Monitoring stack in the repo (Prometheus, Grafana, alert manager) | "Detect outages" | Far larger than the site; adds services to run | Healthcheck on `cloudflared` plus one external uptime check in the runbook |
| Staging stack, parameterised `ENV_NAME`, second Cloudflare Tunnel | Safer testing | One page; PR smoke tests already cover the risk | Add when a second environment really exists |
| Multi-arch (arm64) build, QEMU | Might run on the Pi swarm later | Production is all amd64; slows every build | Keep the existing `shortcut:` comment |
| Image signing (cosign) with admission verification | Supply-chain completeness | Swarm does not verify signatures, so signing protects nothing here | Digest pin plus SHA-pinned Actions |
| Brotli build, custom nginx modules, `more_clear_headers` | Smaller or quieter responses | Custom nginx build to maintain for a 1 KB page | gzip and `server_tokens off` |
| Deeper `HEALTHCHECK` on the web image (headers, robots) | Catch wrong config at runtime | The container cannot know which mode is intended; wrong place for the assertion | Assert headers in CI smoke tests |
| Conditional IPv6 listen via an entrypoint script | Keep IPv6 where available | Custom script in the image for no consumer; the tunnel uses IPv4 | Delete the `[::]` line |
| Lighthouse CI or HTML-validator gate | Quality score | Page is 30 lines; the gate adds a dependency tree | One manual Lighthouse run on the live host after the metadata change |

## Feature Dependencies

```
.dockerignore allow-list ──needs──> Dockerfile COPY paths (deploy/nginx.conf, index.html)
        └──verified by──> PR image build

PR smoke script (test/smoke.sh)
    ├──enables──> PR workflow (build, nginx -t, compose config, actionlint)
    │                 ├──verifies──> Dependabot bumps (actions, nginx, cloudflared)
    │                 └──optionally required by──> status-check ruleset on main
    ├──reused by──> Smoke gate before pin on main
    └──asserts──> CSP, server_tokens, HSTS, COOP/CORP, header-on-404, robots modes

SHA-pinned Actions ──needs a bot──> Dependabot github-actions
Pinned nginx/cloudflared ──needs a bot──> Dependabot docker / docker-compose (+ ignore for the app image)

Pinned cloudflared version ──must support──> `tunnel ready` + TUNNEL_METRICS
    └──enables──> cloudflared healthcheck ──enables──> failure_action: rollback on a bad cloudflared bump

CSP ──constrains──> favicon strategy (data URI needs img-src data:)
og:image ──needs──> .dockerignore allow-list entry + Dockerfile COPY
Metadata (description, OG, canonical) ──independent of──> CSP (meta tags are not blocked)

Ruleset on deploy (no force-push/delete) ──independent of──> pin job auth
Restrict-updates ruleset ──requires──> GitHub App or deploy key in the pin job ──blocks──> human git revert rollback (unless admin bypass)

IPv6 line removal ──independent──> verified only by nginx -t / smoke

README runbook ──last──> documents final versions, healthcheck, ruleset and rollback paths
```

### Dependency Notes

- **Dependabot needs the PR workflow first.** An update PR with no checks is a blind merge into a branch that deploys.
- **Dependabot docker-compose needs an `ignore` for the app image.** The pin job owns that line, and `sha-<commit>` is not a version Dependabot can order.
- **Pinning `cloudflared` comes before its healthcheck.** The check command must exist in the pinned version, and the metrics address becomes part of the pinned run command.
- **CSP and favicon interact.** An inline data-URI icon needs `img-src data:`; a file icon needs `img-src 'self'` and a new asset.
- **`.dockerignore` is verified by the PR build, so it follows the PR workflow.**
- **Rollback runbook text depends on the ruleset choice.** Restrict-updates changes who may revert.
- **Header changes (CSP, COOP/CORP, `server_tokens`, HSTS) are safest after the header probe exists**, so a misplaced `add_header` is caught.

## MVP Definition

### Launch With (this milestone, in order)

- [ ] `test/smoke.sh` + `pull_request` workflow: build, two-mode probes (incl. header on 404), `nginx -t`, `compose config -q`, `actionlint` — foundation; everything else is verified by it
- [ ] Actions pinned to SHAs + `dependabot.yml` for `github-actions`
- [ ] `nginx` and `cloudflared` pinned + Dependabot `docker`/`docker-compose` (with app-image ignore)
- [ ] `cloudflared` healthcheck (exec form, metrics address) on the pinned version
- [ ] Nginx hardening in one change: CSP, `server_tokens off`, HSTS scope decision, remove `listen [::]:80`
- [ ] Page metadata (description, OG text tags, canonical, inline favicon)
- [ ] `.dockerignore` (allow-list), minimal ruleset on `deploy` (no delete, no force-push), README runbook

### Add After Validation (v1.x)

- [ ] Smoke gate before the pin on `main` — once the PR script is stable
- [ ] Required status check on `main` — if Andrei keeps working through PRs
- [ ] `og:image` — when a preview image exists
- [ ] COOP/CORP, `zizmor`, SHA-pin repo setting, `persist-credentials: false`

### Future Consideration (v2+)

- [ ] CI-only `deploy` via GitHub App or deploy key — only if the cheap ruleset proves too weak
- [ ] Digest pin of the app image in the pin step — if rollback bytes drift is ever observed
- [ ] Container runtime hardening (read-only rootfs, `cap_drop`, encrypted overlay) — in CONCERNS.md but not in this milestone's list; separate decision

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| PR smoke script + PR workflow | HIGH | MEDIUM | P1 |
| SHA-pinned Actions + Dependabot actions | HIGH | LOW | P1 |
| Pinned base images + Dependabot docker | HIGH | LOW-MEDIUM | P1 |
| `cloudflared` healthcheck | HIGH | MEDIUM | P1 |
| CSP + `server_tokens off` + HSTS decision | MEDIUM | LOW | P1 |
| IPv6 line removal | MEDIUM | LOW | P1 |
| `.dockerignore` | LOW | LOW | P2 |
| Minimal `deploy` ruleset | MEDIUM | LOW | P1 |
| README runbook | HIGH | LOW | P1 |
| Text metadata + favicon | MEDIUM | LOW | P1 |
| Smoke gate before pin | HIGH | MEDIUM | P2 |
| Required check on `main` | MEDIUM | LOW | P2 |
| `og:image` | MEDIUM | MEDIUM | P2 |
| COOP/CORP, zizmor, SHA-pin setting | LOW | LOW | P3 |
| CI-only `deploy` (App/deploy key) | MEDIUM | HIGH | P3 |
| Digest-pinned app image | MEDIUM | MEDIUM | P3 |

**Priority key:**
- P1: Must have for this milestone
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

Not applicable: this is internal maintenance work, not a product feature set. Reference patterns instead:

| Feature | Common practice | Our approach |
|---------|-----------------|--------------|
| Action pinning | SHA + version comment, Dependabot-updated | Same, all actions incl. first-party |
| Base image pinning | Tag + digest, bot-updated | Same; manual merge, no auto-merge |
| Tunnel health | Community images bake in `cloudflared tunnel ready`; upstream ships none | Compose-level exec-form check |
| Coming-soon SEO | Title, description, OG, favicon | Same, no JSON-LD, no sitemap |

## Open Questions for Requirements

1. HSTS: are all current and planned `*.tropaeum.app` hosts proxied over HTTPS? (Andrei only.)
2. Does Dependabot `docker-compose` pick up `deploy/production/compose.yaml`? (Test with one run.)
3. Does the pinned `cloudflared` version support `tunnel ready`, and does the exec-form check pass in Swarm? (Verify in a throwaway container, not live.)
4. Is a CI-only `deploy` rule wanted at the cost of an App/deploy key, or is delete/force-push protection enough?
5. Is there a preview image for `og:image`?
6. Does Andrei work through PRs (decides the required status check)?
7. Arcane Git Sync settings for the runbook (branch, path, poll interval): not in the repo.

## Sources

- Repo files read 2026-11-02: `Dockerfile`, `deploy/nginx.conf`, `deploy/production/compose.yaml`, `.github/workflows/deploy.yml`, `README.md`, `.planning/PROJECT.md`, `.planning/codebase/CONCERNS.md` (HIGH)
- nginx image IPv6 entrypoint script: [docker-nginx 10-listen-on-ipv6-by-default.sh](https://raw.githubusercontent.com/nginxinc/docker-nginx/master/entrypoint/10-listen-on-ipv6-by-default.sh) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4296) (HIGH, upstream source)
- Cloudflare monitoring page (metrics flag, default metrics address in containers; no `/ready` coverage): [developers.cloudflare.com/tunnel/monitoring](https://developers.cloudflare.com/tunnel/monitoring/) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4320) (HIGH for what it states)
- Upstream cloudflared Dockerfile (distroless, no HEALTHCHECK, user nonroot): [cloudflare/cloudflared Dockerfile](https://raw.githubusercontent.com/cloudflare/cloudflared/master/Dockerfile) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4319) (HIGH)
- `cloudflared tunnel ready` healthcheck pattern: [cloudflared mirror commit "Add healthcheck by default"](https://git.nixnet.services/curben/cloudflared-mirror/commit/a64a7463e10e297d872e8e44d22dc393689ee54a) and community Unraid image pages (MEDIUM, third-party; verify in the pinned version)
- GitHub rulesets overview (bypass for roles, teams, Apps): [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) · [🔖 2026-11-02](https://linkding.lav.ren/bookmarks?details=4297) (HIGH for what it states; it does not address `GITHUB_TOKEN`)
- `GITHUB_TOKEN` not selectable as bypass actor, App/deploy-key workaround, `persist-credentials` pitfall: community PRs and issues, e.g. [MFlowCode/MFC #1466](https://github.com/MFlowCode/MFC/pull/1466), [customerio-reactnative #587](https://github.com/customerio/customerio-reactnative/pull/587) (MEDIUM; confirm against GitHub docs before building)
- Dependabot SHA pin with version-comment updates: [GitHub changelog 2022-10-31](https://github.blog/changelog/2022-10-31-dependabot-now-updates-comments-in-github-actions-workflows-referencing-action-versions/) (HIGH)
- Dependabot docker tag+digest behaviour and `docker-compose` ecosystem: [Microsoft Retina #2228](https://github.com/microsoft/retina/pull/2228), [Dependabot supported ecosystems](https://docs.github.com/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories) (MEDIUM; `compose.yaml` filename coverage unconfirmed)
- Not run: the `research-plan` / `classify-confidence` seam; tiers above are assigned by hand from source type.

---
*Feature research for: static coming-soon site maintenance milestone (tropaeum-web)*
*Researched: 2026-11-02*
