# syntax=docker/dockerfile:1
#
# tropaeum.app — the coming-soon page: one static file on nginx:alpine.
#
# Build locally:
#   docker build -t ghcr.io/elfensky/tropaeum-web:local .

FROM nginx:1-alpine

# Build metadata
ARG COMMIT_SHA=unknown
LABEL org.opencontainers.image.source="https://github.com/elfensky/tropaeum-web"
LABEL org.opencontainers.image.revision="${COMMIT_SHA}"

# Our server block is a template: the nginx image's entrypoint runs envsubst on
# /etc/nginx/templates/*.template (defined env vars only, so $uri & co. survive)
# and writes /etc/nginx/conf.d/default.conf at container start.
RUN rm /etc/nginx/conf.d/default.conf
COPY deploy/nginx.conf /etc/nginx/templates/default.conf.template

# Fails closed: every container is noindex, with a keep-out robots.txt, unless
# its compose says otherwise.
# Only the production stack sets ROBOTS_TAG="" (an empty add_header is not sent).
ENV ROBOTS_TAG="noindex, nofollow"

# Replaces the stock welcome page in the default nginx root
COPY index.html /usr/share/nginx/html/

EXPOSE 80
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost/ >/dev/null 2>&1 || exit 1

CMD ["nginx", "-g", "daemon off;"]
