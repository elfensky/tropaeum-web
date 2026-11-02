---
last_mapped_commit: 005b0e436c23ae67685b4e1b1bc09779227824a8
last_mapped_at: 2026-11-02
---
# Codebase Concerns

**Analysis Date:** 2026-11-02

## Scope and Method

The repository tracks six files: `index.html`, `Dockerfile`, `deploy/nginx.conf`, `deploy/production/compose.yaml`, `.github/workflows/deploy.yml`, and `README.md`. The site is one static page. The rest is the image build, the Swarm stack, and the CI pin pipeline.

Facts below come from these files. Items marked **(inferred)** depend on runtime behavior, on GitHub or Arcane settings that are not in the repo, or on upstream image behavior that was not tested.

## Priority Summary

| # | Concern | Area | Severity |
|---|---------|------|----------|
| 1 | `cloudflared` runs `:latest` with no healthcheck; rollback cannot catch a broken tunnel | Deploy / Stack | High |
| 2 | Third-party actions pinned by major tag, not commit SHA; job holds `contents: write` and `packages: write` | CI | High |
| 3 | Base images are floating tags (`nginx:1-alpine`, `cloudflare/cloudflared:latest`) | Build / Supply chain | Medium |
| 4 | No pre-deploy validation of the nginx config or the rendered image | CI / Build | Medium |
| 5 | `deploy` branch write-protection is a convention, not an enforced rule (inferred) | CI / Governance | Medium |
| 6 | HSTS with `includeSubDomains; preload` on every response, including plain HTTP | Security | Medium |
| 7 | Missing hardening headers and `server_tokens` not disabled | Security | Low |
| 8 | Possible startup failure when the container has no IPv6 (inferred) | Build / Runtime | Medium |
| 9 | Rollback depends on old `sha-` images that no repo mechanism retains (inferred) | Deploy | Medium |
| 10 | Node-label dependency for placement; manual secret bootstrap; no runbook | Ops | Medium |
| 11 | No tests, no lint, no smoke test anywhere in the pipeline | Quality | Medium |
| 12 | Hardcoded repository owner in three places | Maintainability | Low |

## Tech Debt

**Floating base-image and runtime tags:**
- Issue: The image base is `nginx:1-alpine`, a moving tag, and the stack runs `cloudflare/cloudflared:latest`. Neither is pinned by version or digest. The repo pins the app image by commit SHA, which is stricter than the base images it builds on.
- Files: `Dockerfile` (line 8), `deploy/production/compose.yaml` (line 60)
- Impact: A rebuild of the same commit can produce a different image. A new `cloudflared` release can change tunnel behavior on the next task restart or redeploy, with no change in this repo.
- Fix approach: Pin `nginx` to a dated minor tag or digest. Pin `cloudflared` to an explicit version. Record the chosen versions in the compose file so a `git revert` restores the exact prior behavior.

**Mutable `sha-` image tags:**
- Issue: The app image uses the tag `sha-<commit>`. GHCR tags can be overwritten. Nothing in the workflow prevents a re-push under the same tag (inferred from the workflow; GHCR tag immutability settings are not in the repo).
- Files: `.github/workflows/deploy.yml` (lines 62, 93)
- Impact: A `git revert` to an old pin could pull different bytes than the ones that ran before.
- Fix approach: Pin by digest in the pin step (`image: ...@sha256:...`), or enable tag immutability on the package.

**Duplicated, hand-edited image reference:**
- Issue: The compose file hardcodes `ghcr.io/elfensky/tropaeum-web`. The workflow derives the same name from `github.repository`. The Dockerfile label hardcodes the source URL.
- Files: `deploy/production/compose.yaml` (line 32), `.github/workflows/deploy.yml` (line 78), `Dockerfile` (line 12)
- Impact: After a repo rename or transfer, the pin job fails at its `grep` guard (fail-loud, which is good). The Dockerfile label goes stale without any error.
- Fix approach: Accept the loud failure as the safety net, and document the manual edit in the README. Update the Dockerfile label when the repo moves.

**Single environment hardcoded in the pin job:**
- Issue: `ENV_NAME: production` is fixed in the workflow. Adding a staging stack means copying the job and the compose file.
- Files: `.github/workflows/deploy.yml` (line 77)
- Impact: Low today. Adds work when a second environment is needed.
- Fix approach: Parameterize the job by environment when a second stack exists.

**Docker build context is the full repository:**
- Issue: No `.dockerignore` exists. The build context includes `.git/`, `.github/`, and `deploy/`.
- Files: `Dockerfile` (no ignore file present in repo)
- Impact: Slower context transfer. The final image is not affected, because the Dockerfile copies only two files.
- Fix approach: Add a `.dockerignore` that excludes `.git`, `.github`, `deploy`, and `*.md`.

## Known Bugs

**Possible nginx startup failure without IPv6 (inferred, not verified):**
- Symptoms: The container exits at start, with an error about binding `[::]:80`.
- Files: `deploy/nginx.conf` (lines 3, listen directive `[::]:80`), `Dockerfile` (line 18, removes the stock `default.conf`)
- Trigger: A container network without IPv6. The nginx image's `10-listen-on-ipv6-by-default.sh` script edits `/etc/nginx/conf.d/default.conf` only. This Dockerfile removes that file and writes the rendered config from a template, so the script may run before the file exists and leave the `[::]` listener in place (inferred from the image layout).
- Workaround: None in repo. Run `docker run` on a network with IPv6 disabled to confirm or rule this out.

**Empty `add_header` behavior depends on nginx semantics:**
- Symptoms: If nginx sends an empty `X-Robots-Tag` value, production would send a blank header. Comments say nginx skips empty values.
- Files: `deploy/nginx.conf` (line 24), `deploy/production/compose.yaml` (line 37)
- Trigger: Any change in nginx behavior. The `envsubst` step must also treat an empty `ROBOTS_TAG` as defined. The image's envsubst variable list is built from the environment (inferred).
- Workaround: Verify with `curl -I` against a production-mode run (`docker run -e ROBOTS_TAG=''`). The README gives the command.

## Security Considerations

**`cloudflared` has no healthcheck and no version pin:**
- Risk: The tunnel can fail while the task stays "running". Swarm then keeps it as healthy. `failure_action: rollback` in the update config does not fire, because Swarm has no health signal for this service.
- Files: `deploy/production/compose.yaml` (lines 59-84)
- Current mitigation: Two replicas register on the same tunnel. Cloudflare routes to the surviving connector.
- Recommendations: Pin the image version. Add a healthcheck, or a monitor that checks the public hostname from outside. Document how to detect a dead tunnel.

**Supply-chain exposure in CI:**
- Risk: Actions are referenced by major tag (`actions/checkout@v4`, `docker/setup-buildx-action@v3`, `docker/login-action@v3`, `docker/build-push-action@v6`). A compromised tag changes code that runs with `packages: write` and `contents: write` on the `pin` and `build` jobs.
- Files: `.github/workflows/deploy.yml` (lines 41, 44, 47, 56, 82)
- Current mitigation: Top-level `permissions: contents: read`. Job-level grants are narrow. The `pin` job has `contents: write` only.
- Recommendations: Pin each action to a full commit SHA with a version comment. Enable Dependabot for `github-actions` to keep the SHAs current.

**Write access to `deploy` is a convention:**
- Risk: The comments say CI is the only writer of `deploy`. Nothing in the repo enforces this. A human with push rights can edit the pinned image, and Arcane applies it (inferred; repository rules are not visible in the repo).
- Files: `deploy/production/compose.yaml` (lines 3-7), `.github/workflows/deploy.yml` (lines 9-11)
- Current mitigation: Comments only.
- Recommendations: Add a branch ruleset on `deploy` that allows only the `github-actions[bot]` actor to push. Require review or restrict deletion.

**HSTS with `preload` and `includeSubDomains`:**
- Risk: `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload` commits the apex and every subdomain to HTTPS for one year. The `preload` token only has effect after manual submission to the preload list, which is not in the repo. The header is also sent on plain HTTP port 80, where browsers ignore it.
- Files: `deploy/nginx.conf` (line 19)
- Current mitigation: Cloudflare terminates TLS for the public hostnames.
- Recommendations: Confirm every current and planned subdomain of `tropaeum.app` serves HTTPS before keeping `includeSubDomains`. Send HSTS only on the HTTPS side, or accept the no-op on HTTP and document it. Do not submit to the preload list without that check.

**No Content-Security-Policy:**
- Risk: No CSP header is set. The page has no scripts today, so the practical exposure is low. Any future script or injected markup has no second line of defense.
- Files: `deploy/nginx.conf` (header block, lines 14-19), `index.html`
- Current mitigation: `index.html` has no `<script>` tags and no external resources. The README states this.
- Recommendations: Add `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'self'` for this page. Adjust when the site gains assets.

**Server version disclosure:**
- Risk: `server_tokens` is not set to `off`, so nginx reports its version in the `Server` header.
- Files: `deploy/nginx.conf` (server block)
- Current mitigation: None.
- Recommendations: Add `server_tokens off;` to the server block.

**Plain HTTP between cloudflared and web on the overlay network (inferred):**
- Risk: The overlay network `internal` is declared without `driver_opts: encrypted`. Traffic between `cloudflared` and `web` on different nodes is unencrypted on the wire (inferred from standard Swarm overlay behavior).
- Files: `deploy/production/compose.yaml` (lines 19-21)
- Current mitigation: The stack is internal to the cluster. Only `cloudflared` attaches to `internal`, besides `web`.
- Recommendations: Add `driver_opts: { encrypted: "true" }` to the `internal` network if the cluster network is not trusted. Measure the performance cost first.

**Container runs as root and has no runtime hardening:**
- Risk: The nginx master process runs as root (image default). The compose file sets no `read_only`, `cap_drop`, or `security_opt`.
- Files: `Dockerfile` (no `USER` directive), `deploy/production/compose.yaml` (`web` service)
- Current mitigation: Port 80 requires root in the default config. The service has resource limits.
- Recommendations: Add `read_only: true` with `tmpfs` mounts for `/var/cache/nginx` and `/var/run`, and `cap_drop: [ALL]` with the minimal capabilities nginx needs. Run on an unprivileged port if the stack allows.

**Secret bootstrap is manual and undocumented beyond a comment:**
- Risk: The `tropaeum_cloudflared` secret must exist before the stack deploys. Its creation command, rotation steps, and the owner of the tunnel token are not in the repo.
- Files: `deploy/production/compose.yaml` (lines 11-12, 23-25)
- Current mitigation: The comment names the secret and the tunnel.
- Recommendations: Add a short runbook section to `README.md`: create, rotate, and revoke the token. Record who holds the Cloudflare account access.

## Performance Bottlenecks

**No cache headers on the static page:**
- Problem: `deploy/nginx.conf` sets no `Cache-Control` or `expires` directive. Browsers revalidate `index.html` on each visit.
- Files: `deploy/nginx.conf` (location `/`, lines 42-44)
- Cause: Defaults only. Nginx sends `ETag` and `Last-Modified`.
- Improvement path: Add `Cache-Control: no-cache` for HTML and a longer `max-age` for assets once any assets exist.

**No measured performance data:**
- Problem: The repo has no load test, no Lighthouse run, and no timing data. Performance claims cannot be checked from the repo.
- Files: none
- Cause: Not in scope for a coming-soon page today.
- Improvement path: Run a one-time Lighthouse check against the production hostname when the page changes.

## Fragile Areas

**Config template and header inheritance:**
- Files: `deploy/nginx.conf`, `Dockerfile` (lines 15-19)
- Why fragile: The file is an envsubst template. Any `$name` that matches a defined environment variable is replaced. The file says no `add_header` may appear in any `location`, because a location-level `add_header` drops every server-level one. This rule is in a comment only. A future location block with `add_header` would silently remove HSTS, CSP, and `X-Robots-Tag`.
- Safe modification: Add `add_header` only at server level. Run `nginx -t` in the container after any change. Check `curl -I` for every header on each location.
- Test coverage: None. No header test exists.

**`robots.txt` depends on an `if` in a location:**
- Files: `deploy/nginx.conf` (lines 34-40)
- Why fragile: `if` inside `location` is a known nginx pitfall. This use is safe only because the block contains a single `return` and a `try_files` fallback. Adding a rewrite or a second `if` changes behavior.
- Safe modification: Keep the block to one `return`. Test both modes: `ROBOTS_TAG` set and `ROBOTS_TAG=''`.
- Test coverage: None.

**Fail-closed indexing switch spans three files:**
- Files: `Dockerfile` (line 24), `deploy/nginx.conf` (lines 21-25), `deploy/production/compose.yaml` (lines 35-37), `README.md` (lines 21-22)
- Why fragile: Production indexability depends on `ROBOTS_TAG: ''` in the compose file. A new stack copied from this one, without that line, becomes non-indexable. A stack that sets the value wrongly can index staging.
- Safe modification: Change `ROBOTS_TAG` only in the compose file for the target environment. Verify with `curl -I https://<host>/` after deploy.
- Test coverage: None.

**Pin job parses YAML with `grep` and `sed`:**
- Files: `.github/workflows/deploy.yml` (lines 84-97)
- Why fragile: The `grep` and `sed` patterns match the literal image line. The dots in `ghcr.io` act as regex wildcards, and a trailing comment on the `image:` line changes the rendered output. Comments in the file warn about this, but nothing enforces it.
- Safe modification: Keep the `image:` line in the form `image: ghcr.io/<owner>/<repo>:<tag>` with no trailing comment. Confirm the `grep` guard still passes after any edit.
- Test coverage: The job itself is the only test. It runs only on push to `main`.

**Shallow fetch and rebuild loop in the pin job:**
- Files: `.github/workflows/deploy.yml` (lines 104-129)
- Why fragile: On each retry, the job re-fetches `deploy` with `--depth=1` and rewrites the file. The retry works only because the concurrency group serializes runs per ref. Removing that group would allow two pins to race.
- Safe modification: Keep `concurrency.cancel-in-progress: false`. Do not parallelize the pin job.
- Test coverage: None.

**Deploy path depends on an external tool:**
- Files: `deploy/production/compose.yaml` (lines 5-6), `README.md` (lines 14-16)
- Why fragile: Arcane Git Sync applies the `deploy` branch. The sync configuration, its credentials, and its state live outside the repo (inferred).
- Safe modification: Record the Arcane project settings (branch, path, and poll interval) in the README.
- Test coverage: None.

## Scaling Limits

**Placement depends on node labels:**
- Current capacity: Both `web` and `cloudflared` require the node label `role == apps`. The repo does not create or check that label.
- Limit: With fewer than two labeled nodes, `web` spreads poorly. With zero labeled nodes, both services stay pending.
- Scaling path: Document the label command in the README. Add a check step that confirms the label count before deploy.

**Replica counts and resource limits:**
- Current capacity: `web` runs 2 replicas at 0.50 CPU and 128M memory each. `cloudflared` runs 2 replicas at 0.25 CPU and 128M memory each.
- Limit: Not measured. For a static page this is ample. Limits are set without load data.
- Scaling path: Raise replicas or limits only after a measured need. Keep `spread: node.id` for `web`.

## Dependencies at Risk

**`cloudflare/cloudflared:latest`:**
- Risk: Unpinned. Its tunnel token option (`TUNNEL_TOKEN_FILE`) is a newer setting. Support depends on the release that Swarm pulls (inferred from the variable name; the version that supports it is not stated in the repo).
- Impact: A pull of `latest` on a new task can change behavior or fail to start.
- Migration plan: Pin a version that the team has tested. Note the minimum version that supports `TUNNEL_TOKEN_FILE`.

**`nginx:1-alpine`:**
- Risk: Floating minor tag. The image updates with upstream security releases, which is useful, but the build is not reproducible from the repo alone.
- Impact: Rebuilds of the same commit can differ.
- Migration plan: Pin a dated tag or digest. Update it on a schedule with the same pin process used for the app.

**GitHub Actions pinned by major tag:**
- Risk: See the Security section above.
- Impact: CI code that runs with write permissions can change without a repo change.
- Migration plan: Pin to commit SHAs and enable Dependabot for `github-actions`.

## Missing Critical Features

**No pre-deploy validation:**
- Problem: No step runs `nginx -t` on the rendered config, `docker compose config` or `docker stack config` on the compose file, or an HTML check on `index.html`. A broken config reaches `deploy` after the image is built and pushed.
- Blocks: Early detection of config errors. The start-first rollout and the image healthcheck limit the damage, but only after the pin is live.
- Files: `.github/workflows/deploy.yml`, `Dockerfile`

**No smoke test of the built image:**
- Problem: The pipeline does not run the image before pushing the pin. It does not check that `/` returns 200, or that `X-Robots-Tag` and HSTS appear as intended.
- Blocks: A pre-pin gate. A pin can point at an image that starts but serves wrong headers.
- Files: `.github/workflows/deploy.yml` (between the build and pin jobs)

**No image retention or cleanup policy:**
- Problem: Each push creates a new `sha-` tag in GHCR. The repo has no retention rule.
- Blocks: Rollback past the retained window (inferred: GHCR retention is set in package settings, not in the repo).
- Files: `.github/workflows/deploy.yml`

**No monitoring or alerting in the repo:**
- Problem: No uptime check, no error tracking, and no alerts for the tunnel or the containers are configured in the repo.
- Blocks: Detecting an outage without a visitor report.
- Files: `deploy/production/compose.yaml`

**No security headers beyond the basic set:**
- Problem: CSP, `Cross-Origin-Opener-Policy`, and `Cross-Origin-Resource-Policy` are not set. See Security Considerations.
- Blocks: Hardening score on external scanners.
- Files: `deploy/nginx.conf`

**No SEO or sharing metadata:**
- Problem: `index.html` has no `<meta name="description">`, no Open Graph tags, and no `<link rel="icon">`. Production is indexable (`ROBOTS_TAG: ''`), so search engines index a page with a bare title.
- Blocks: Search and link previews.
- Files: `index.html` (head, lines 3-28)

## Test Coverage Gaps

**No automated tests of any kind:**
- What's not tested: The page content, the nginx config, the `robots.txt` branch, header presence, and the compose file's validity.
- Files: `index.html`, `deploy/nginx.conf`, `deploy/production/compose.yaml`
- Risk: A change that breaks a header or the indexing switch is found only after production deploy.
- Priority: High for the header and indexing behavior. Low for the static HTML.

**Image healthcheck tests only the root path:**
- What's not tested: The healthcheck (`Dockerfile` lines 31-32) requests `/` and treats any successful response as healthy. It does not check headers, `robots.txt`, or the config mode.
- Files: `Dockerfile` (lines 31-32)
- Risk: A container can pass health with the wrong `X-Robots-Tag` value.
- Priority: Medium.

**No linting of the workflow or compose file:**
- What's not tested: YAML syntax, Actions workflow errors, and compose schema.
- Files: `.github/workflows/deploy.yml`, `deploy/production/compose.yaml`
- Risk: A syntax error in the pin job blocks deploys with a late failure.
- Priority: Medium.

---

*Concerns audit: 2026-11-02*
