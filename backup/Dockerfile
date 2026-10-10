# Weekly off-site database backup (issue #54), run by the Render cron job in
# render.yaml. Postgres 16 tools to match the server (the app image's Debian
# pg_dump is 15, which refuses a 16 server), plus age to encrypt and curl/jq
# to talk to the GitHub API.
FROM docker.io/library/postgres:16-bookworm

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y age ca-certificates curl jq && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY backup.sh /usr/local/bin/backup
COPY restore.sh /usr/local/bin/restore

USER postgres
ENTRYPOINT []
CMD ["backup"]
