# tropaeum-web

The website of [tropaeum.app](https://tropaeum.app). Today it is a one-page
coming-soon site: `index.html` (plain HTML and inline CSS, no scripts, no
external requests, no tracking) served by `nginx:1-alpine`.

## How it deploys

- **Image:** every push to `main` builds `ghcr.io/elfensky/tropaeum-web:sha-<commit>`
  (`.github/workflows/deploy.yml`).
- **Pin:** the same workflow renders `deploy/production/compose.yaml` with that
  tag and commits it to the `deploy` branch. CI is the only writer of `deploy`.
  The copy on `main` carries `:sha-unpinned` and is never deployed as-is.
- **Stack:** Docker Swarm stack `tropaeum` on the production swarm (services
  `web` and `cloudflared`, 2 replicas each, on `role == apps` nodes). Arcane Git
  Sync applies `deploy/production/compose.yaml` from the `deploy` branch.
- **Tunnel:** ingress is the stack's own Cloudflare Tunnel
  `tropaeum.app (production)`. Its token is the external Swarm secret
  `tropaeum_cloudflared`; the public hostnames (apex and `www` →
  `http://web:80`) live in the Zero Trust dashboard.
- **Indexing:** the image fails closed (`X-Robots-Tag: noindex, nofollow` and a
  keep-out `robots.txt`); the production compose sets `ROBOTS_TAG: ''`.

## Rollback

`git revert` the pin commit on the `deploy` branch and push. Arcane Git Sync
applies the previous image. Never `docker stack deploy` by hand.

## Run locally

    docker build -t tropaeum-web:local .
    docker run --rm -p 8080:80 -e ROBOTS_TAG='' tropaeum-web:local

Then open http://localhost:8080.
