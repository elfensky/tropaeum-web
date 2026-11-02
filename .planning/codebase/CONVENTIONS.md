---
last_mapped_commit: 005b0e436c23ae67685b4e1b1bc09779227824a8
last_mapped_at: 2026-11-02
---
# Coding Conventions

**Analysis Date:** 2026-11-02

## Scope of the Repository

The repository holds six tracked files and no application code:

- `index.html` - the whole site (HTML plus inline CSS, no scripts)
- `Dockerfile` - builds the image on `nginx:1-alpine`
- `deploy/nginx.conf` - server block, installed as an nginx template
- `deploy/production/compose.yaml` - Docker Swarm stack for production
- `.github/workflows/deploy.yml` - build, push, and pin workflow
- `README.md` - project overview, deploy flow, rollback, local run

There is no language runtime, package manager, linter config, formatter config, or `.editorconfig`. The conventions below are the patterns the existing files follow. They are not enforced by tooling.

## Formatting Observed Across Files

**Indentation:**
- 2 spaces in `index.html`, `deploy/nginx.conf`, `deploy/production/compose.yaml`, and `.github/workflows/deploy.yml`.
- 4 spaces inside the `<style>` block of `index.html`. Treat this as the exception: the CSS rules nest inside a `@media` block, and the file uses 4 spaces there.
- Tabs are not used.

**Line length:**
- Comments wrap near 80 columns in `Dockerfile`, `deploy/nginx.conf`, `deploy/production/compose.yaml`, and `.github/workflows/deploy.yml`.
- Keep new comments under 80 columns to match.

**Trailing newlines:** Every file ends with one newline.

## HTML and CSS (`index.html`)

**Document shape:**
- Start with lowercase `<!doctype html>` and set `<html lang="en">`.
- The `<head>` order is: `meta charset`, `meta viewport`, `meta color-scheme`, `title`, then one inline `<style>` block.
- Do not add `<script>` tags. The file states "no scripts, no external requests, no tracking" in `README.md`. Keep that rule.
- Do not load fonts, stylesheets, or images from a CDN or other external host. Use only the system font stack already set in `body`.

**Attribute quoting:** Use double quotes for all attributes, for example `<meta charset="utf-8">` and `<a href="https://lav.ren">`.

**Element spacing:** Put each block element on its own line. Keep content inside `<main>` as the single landmark wrapper.

**CSS:**
- Declare colours as custom properties on `:root` (`--bg`, `--fg`, `--link`). Reference them with `var(--name)`.
- Put dark-mode values in `@media (prefers-color-scheme: dark)` on `:root`. Do not hard-code colours in element rules.
- Write each declaration on one line when it fits, for example `margin: 0;`. Put a multi-property rule on separate lines when it has more than four declarations, as `body` does.
- Keep `font` as the shorthand `font: 1.125rem/1.5 system-ui, sans-serif;`.
- Use `rem` for sizes.

## nginx Configuration (`deploy/nginx.conf`)

**Layout:**
- One `server` block. Directives come first, in this order: `listen`, `root`, `index`, then `gzip` settings, then header settings, then `location` blocks.
- Use 2-space indentation and a blank line between logical groups.

**Comments:** Each group has a comment that says why the directive exists. Examples: the `# Security / hygiene headers` group and the `# No add_header inside any location below` note. Follow this pattern for every new directive.

**Headers:**
- Declare every header with `add_header <name> "<value>" always;`. The `always` flag is required so error responses carry the headers.
- Declare headers only at server level. Do not add `add_header` inside a `location`. A `location` that declares its own `add_header` drops every server-level header. The file states this rule in a comment.

**Templating:**
- `deploy/nginx.conf` is an nginx-image template, copied to `/etc/nginx/templates/default.conf.template`. Only variables that are defined in the container environment are substituted by `envsubst`. The current variable is `${ROBOTS_TAG}`.
- Use `$robots_tag` (a `set` variable) for runtime `if` checks. Keep the template variable in the `set` line only.
- Do not add other `$` variables without defining them in the container environment. Undefined names are left as-is.

**Naming:** nginx variables use lower snake case (`$robots_tag`). Template variables use upper snake case (`${ROBOTS_TAG}`).

## Dockerfile

- Start with `# syntax=docker/dockerfile:1`, then a comment block that names the purpose and gives a local build command.
- Pin the base by major line: `FROM nginx:1-alpine`. Do not use `latest`.
- Put `ARG` and `LABEL` lines together after `FROM`. Use OCI label keys, for example `org.opencontainers.image.source`.
- Set safe defaults with `ENV` and document why in a comment above it. The current default is `ENV ROBOTS_TAG="noindex, nofollow"`.
- Use one `COPY` per file. Place the config under `/etc/nginx/templates/` and the site under `/usr/share/nginx/html/`.
- Use the exec form for `CMD` (`CMD ["nginx", "-g", "daemon off;"]`).
- Declare `EXPOSE 80` and `STOPSIGNAL SIGQUIT` before `HEALTHCHECK`.
- Use `HEALTHCHECK` with explicit `--interval`, `--timeout`, `--start-period`, and `--retries` flags, and end the check command with `|| exit 1`.

## Docker Swarm Stack (`deploy/production/compose.yaml`)

**Comment rules:** The file header states the operating rules: source of truth, who writes the pin, prerequisites, and rollback. Keep these rules in the header when you edit the file.

**Image pin contract:**
- The `web` service line must match the pattern `image: ghcr.io/elfensky/tropaeum-web:` exactly. The CI job searches for this pattern with `grep -qE`.
- The tag on `main` is the placeholder `sha-unpinned`. Do not replace it by hand, on `main` or on `deploy`.
- Do not put a comment on the same line as the `image:` value. The CI `sed` replaces everything after the colon.

**Key naming:** Service names are lowercase, one word: `web`, `cloudflared`. Network and secret names use `tropaeum_` for the secret and a plain name for the network (`internal`).

**Environment values:** Quote an empty string explicitly: `ROBOTS_TAG: ''`. Add a comment that states what an empty value does.

**Resources and deploy policy:** Each service sets `resources.limits` and `update_config` with `order: start-first`. Each service uses `restart_policy.condition: any`.

## GitHub Actions Workflow (`.github/workflows/deploy.yml`)

**Structure:**
- Top-level keys in order: `name`, the comment block, `on`, `permissions`, `concurrency`, `jobs`.
- Each job has `name`, `runs-on`, `timeout-minutes`, `permissions`, then `steps`.
- Give each step a `name:`. Use a comment above a step when it explains a constraint.

**Permissions:** Set `permissions` at workflow level to `contents: read`. Grant more only on the job that needs it. Build uses `packages: write`. Pin uses `contents: write`.

**Action versions:** Pin each action to a major tag: `actions/checkout@v4`, `docker/setup-buildx-action@v3`, `docker/login-action@v3`, `docker/build-push-action@v6`.

**Expressions:** Use `${{ github.sha }}`, `${{ github.ref_name }}`, and `${{ secrets.GITHUB_TOKEN }}` directly in `with:` and `if:`. Pass values into shell steps through `env:` (`env: IMAGE: ...`), then read them as `$IMAGE` in the script.

**Shell style inside `run:` blocks:**
- Use `src=`, `publish()`, and `for ... do ... done` as the shell forms.
- Do not set `set -e`. Each failing command is guarded with `|| { ...; exit 1; }` or `|| return 1`.
- Print failures as `echo "::error::..."` and retries as `echo "::warning::..."`.
- Use `-q` on `git` commands that run in CI, and `-m` with a message for every commit.
- Write temporary files to `$RUNNER_TEMP`.

**Guard style:** Before a destructive or pinned edit, check that the target exists. Example: `grep -qE "^[[:space:]]*image: ${IMAGE}:" "$src" || { ...; exit 1; }`. Follow this pattern for any new edit step.

**Concurrency:** Keep `cancel-in-progress: false` for the pin path. A cancelled run can leave `deploy` in a half-written state.

**Trigger filters:** `paths-ignore` lists root `*.md` only. Use the comment form that explains the glob: a single `*` does not cross `/`.

## Commit Messages

The history uses Conventional Commit prefixes:

- `build:` for image and build changes (`build: coming-soon page on an nginx image`)
- `deploy:` for stack and pipeline changes (`deploy: production stack tropaeum and the pin job`)
- `chore(deploy): <env> → sha-<12 chars>` for the bot pin commits on the `deploy` branch, written by CI

Merges use GitHub's default `Merge pull request #N from <owner>/<branch>` form. Branch names in the history use `feat/<topic>`.

Commit messages on `deploy` are written only by `github-actions[bot]`. Do not write to `deploy` by hand. Roll back with `git revert` of the pin commit, as `README.md` states.

## Documentation

- `README.md` is the single human-facing document. It uses `##` sections: "How it deploys", "Rollback", "Run locally".
- Root `*.md` files do not trigger a build (see `paths-ignore` in `.github/workflows/deploy.yml`).
- Inline comments are the main place where the reasons for a rule are recorded. Keep those comments accurate when a rule changes.

## Error Handling

- Configuration files fail closed by default. The image sets `ROBOTS_TAG` to `noindex, nofollow`, and only the production compose overrides it.
- CI fails loudly. Each check exits 1 with a `::error::` message. A check never passes silently when its pattern does not match.
- The pin job retries a rejected push up to three times, fetching a fresh copy of `deploy` each time and not rebasing (`publish()` in `.github/workflows/deploy.yml`).

## Secrets and Sensitive Values

- No secret values appear in tracked files. The Cloudflare tunnel token is an external Swarm secret named `tropaeum_cloudflared`, referenced by name only in `deploy/production/compose.yaml`.
- Registry login uses `${{ secrets.GITHUB_TOKEN }}`, not a stored token.
- Keep new secrets out of the repo. Reference them by name, as the compose file does.

## Naming Summary

| Kind | Convention | Example |
|------|-----------|---------|
| HTML/CSS custom property | `--kebab-case` | `--bg`, `--link` |
| nginx runtime variable | `$snake_case` | `$robots_tag` |
| nginx template variable | `${UPPER_SNAKE}` | `${ROBOTS_TAG}` |
| Compose service | lowercase, one word | `web`, `cloudflared` |
| Compose secret | `tropaeum_` prefix | `tropaeum_cloudflared` |
| Workflow job | lowercase, one word | `build`, `pin` |
| Workflow env var | `UPPER_SNAKE` | `ENV_NAME`, `IMAGE`, `SHA` |
| Shell function in `run:` | lowercase | `publish` |
| Image tag | `sha-<full commit SHA>` | `sha-005b0e4...` |

---

*Convention analysis: 2026-11-02*
