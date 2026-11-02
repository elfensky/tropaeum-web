# tropaeum-web

The website of tropaeum.app: today a one-page coming-soon site on nginx, deployed to the production swarm through the CI pin on the `deploy` branch (see `README.md`).

## Life cockpit

Tracked in the life-cockpit vault under `#drunik` (tracker: `elfensky/tropaeum-web`). The cockpit is the
control plane (what to work on); this repo is where the work happens. Report progress by
opening/closing issues and PRs as usual — the cockpit pulls from the tracker on its next
`/sync`. Nothing to update in the vault; don't mirror cockpit state (milestones, due dates) here.
GSD projects: after `/gsd-new-project`, run `/cockpit-gsd-profile` once in this repo before planning the first slice.
Roadmap: this repo owns its roadmap. `.planning/ROADMAP.md` (GSD) is the one roadmap file here; no second
roadmap file lives in this repo. A session in this repo publishes it to projects.static.lav.ren through
keijiban (`elfensky/keijiban`); the vault keeps the enrollment only, never a copy of the plan.
