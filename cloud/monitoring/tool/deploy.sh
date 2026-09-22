#!/usr/bin/env bash
# Pushes the monitoring stack's configuration to bob:/opt/flutter3d-monitoring
# and brings the containers up. Nothing here is compiled — the whole stack is
# two off-the-shelf images and the config files beside this script — so a
# redeploy is a sync and a `docker compose up -d`, not a build.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${FLUTTER3D_MONITORING_HOST:-bob}"
target="${FLUTTER3D_MONITORING_PATH:-/opt/flutter3d-monitoring}"

ssh "$host" "mkdir -p $target"

# --delete, because a dashboard removed from grafana/dashboards/ must stop
# being provisioned. tool/ is excluded: this script has no business copying
# itself, and deploy.sh does not need to exist twice on the machine it runs
# from.
rsync -az --delete --exclude 'tool/' "$here/" "$host:$target/"

# `docker compose up -d` alone picks up a changed prometheus.yml or dashboard
# JSON without a restart — both are bind-mounted read-only and Grafana's file
# provider re-reads its directory every 30s (see
# grafana/provisioning/dashboards/dashboards.yml). A changed docker-compose.yml
# itself — a new image tag, a new env var — is what actually needs this.
ssh "$host" "cd $target && docker compose up -d"

echo "deployed to https://grafana.pleion.dev/"
