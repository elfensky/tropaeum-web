---
last_mapped_commit: 005b0e436c23ae67685b4e1b1bc09779227824a8
last_mapped_at: 2026-11-02
---
# Codebase Structure

**Analysis Date:** 2026-11-02

## Directory Layout

```
tropaeum-web/                          # repo root (git worktree in this session)
├── .github/
│   └── workflows/
│       └── deploy.yml                 # Build, push image, pin tag on `deploy` branch
├── deploy/
│   ├── nginx.conf                     # nginx server block (installed as a template)
│   └── production/
│       └── compose.yaml               # Swarm stack `tropaeum` (image tag rewritten by CI)
├── Dockerfile                         # nginx:1-alpine image with the page and config
├── index.html                         # The coming-soon page (only content)
├── README.md                          # Deploy, rollback, and local run notes
└── .planning/                         # GSD planning docs (not part of the site)
    └── codebase/                      # Codebase map documents (this file's folder)
```

Only six files are tracked by git (`git ls-files`):

- `.github/workflows/deploy.yml`
- `Dockerfile`
- `README.md`
- `deploy/nginx.conf`
- `deploy/production/compose.yaml`
- `index.html`

## Directory Purposes

**`.github/workflows/`:**
- Purpose: GitHub Actions workflow definitions.
- Contains: One workflow, `deploy.yml`.
- Key files: `.github/workflows/deploy.yml`

**`deploy/`:**
- Purpose: Server config and deployment descriptions. Everything the image and the stack need, apart from the page itself.
- Contains: nginx config and the production compose file.
- Key files: `deploy/nginx.conf`, `deploy/production/compose.yaml`

**`deploy/production/`:**
- Purpose: The production stack. Path name is the environment name. CI reads `ENV_NAME: production` and writes `deploy/$ENV_NAME/compose.yaml` (`.github/workflows/deploy.yml`).
- Contains: `compose.yaml` only.
- Key files: `deploy/production/compose.yaml`

**Repo root:**
- Purpose: Image build inputs and the page.
- Contains: `Dockerfile`, `index.html`, `README.md`.
- Key files: `Dockerfile`, `index.html`

**`.planning/`:**
- Purpose: GSD workflow documents. Not used by the build or deploy.
- Contains: `codebase/` (this map). The `Dockerfile` copies only `deploy/nginx.conf` and `index.html`, so `.planning/` does not enter the image.
- Generated: No. Committed: Not in the tracked file list at the time of analysis.

## Key File Locations

**Entry Points:**
- `index.html`: The page served at `/`.
- `deploy/nginx.conf`: The HTTP server on port 80. Its `server` block is the request entry for the container.
- `.github/workflows/deploy.yml`: The build and pin entry, run on push to `main`.
- `deploy/production/compose.yaml`: The stack entry used by Arcane Git Sync.

**Configuration:**
- `Dockerfile`: Image build settings, `ROBOTS_TAG` default, healthcheck, `CMD`.
- `deploy/nginx.conf`: Security headers, gzip settings, robots handling, location rules.
- `deploy/production/compose.yaml`: Replicas, placement constraint `node.labels.role == apps`, rollout policy, resource limits, `ROBOTS_TAG: ''`, secret reference.

**Core Logic:**
- None. The repo contains no application code, scripts, or build tooling.

**Testing:**
- None. No test files, test config, or test workflow exist in the repo.

**Documentation:**
- `README.md`: Deploy flow, rollback, local run.

## Naming Conventions

**Files:**
- Root and top-level files use UPPERCASE for documentation (`README.md`) and lowercase for source (`index.html`, `Dockerfile`).
- Config files use lowercase words: `nginx.conf`, `compose.yaml`.
- Workflow files use lowercase: `deploy.yml`.
- Compose files use the `.yaml` extension. The workflow file uses `.yml`. Keep the existing mixed usage unless a change needs both.

**Directories:**
- Lowercase, single words: `deploy`, `production`, `workflows`.
- Environment directories under `deploy/` match the CI variable `ENV_NAME`. Adding `deploy/staging/` requires a matching value in the workflow.

**Image and stack names:**
- Image: `ghcr.io/elfensky/tropaeum-web` (`Dockerfile`, `.github/workflows/deploy.yml`).
- Stack: `tropaeum` (`deploy/production/compose.yaml` header).
- Service names: `web`, `cloudflared`. `web` is the DNS name used by the tunnel (`http://web:80`).
- Secret: `tropaeum_cloudflared`.

## Where to Add New Code

**New static page or section:**
- Primary code: `index.html`. The file is self-contained. Keep inline CSS in the `<style>` block. The page must not load external scripts or assets, per `README.md`.
- Tests: None in the repo.

**New static asset (image, font, script):**
- Place next to `index.html` at the repo root, or in a new subfolder. `Dockerfile` copies only `index.html` today. Add a `COPY` line for each new file or folder: `COPY assets/ /usr/share/nginx/html/assets/`.
- Note: A new script or external request conflicts with the "no scripts, no external requests" statement in `README.md`. Confirm that change first.

**New server behavior (headers, routes, redirects):**
- Primary code: `deploy/nginx.conf`.
- Follow the rule that `location` blocks must not declare `add_header` (see `ARCHITECTURE.md`, Architectural Constraints).

**New environment (for example staging):**
- Config: `deploy/<env>/compose.yaml`. Copy the structure from `deploy/production/compose.yaml`.
- Pipeline: Extend `.github/workflows/deploy.yml` with the new env. The current `pin` job checks `if: github.ref_name == 'main'` and pins only `production`.

**New build step or CI job:**
- Primary code: `.github/workflows/deploy.yml`. Add a job with `needs: build` to reuse the image.

**Documentation:**
- `README.md` at the repo root. Root `*.md` changes do not trigger the deploy workflow (`paths-ignore: '*.md'`).

**Utilities or shared helpers:**
- None exist. There is no shared code layer in this repo.

## Special Directories

**`deploy/production/`:**
- Purpose: Production stack definition.
- Generated: Partly. The `image:` line is rewritten by CI on the `deploy` branch. The copy on `main` keeps the placeholder `sha-unpinned`.
- Committed: Yes, on `main` (placeholder) and on `deploy` (pinned, written only by CI).

**`.planning/`:**
- Purpose: GSD planning and codebase map documents.
- Generated: Yes, by GSD mapper agents.
- Committed: Not in the tracked file list at the time of analysis.

**`deploy` branch (git, not a directory on `main`):**
- Purpose: Holds `deploy/production/compose.yaml` with the real image tag. Arcane Git Sync reads it.
- Generated: Yes, by job `pin` in `.github/workflows/deploy.yml`.
- Committed: Yes, CI commits only. Do not edit by hand.

---

*Structure analysis: 2026-11-02*
