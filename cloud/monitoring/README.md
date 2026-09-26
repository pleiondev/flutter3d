# monitoring

Prometheus and Grafana for https://models.pleion.dev/, at
https://grafana.pleion.dev/. The dashboard shows how many accounts exist, how
many are verified, how many models have been uploaded, and how many bytes they
hold on disk. These are the counts [cloud/README.md](../README.md) exists to
answer, and nobody wants to SSH in and query Postgres for them.

The models service reports its own numbers at `GET /metrics`, in the text
format Prometheus scrapes (see `cloud/server/lib/src/http/metrics.dart` and
`cloud/server/lib/src/db/metrics_repository.dart`). This directory turns that
endpoint into a dashboard. Nothing here is compiled: it is two off-the-shelf
images and the config beside them.

## What is here

| | |
|---|---|
| `docker-compose.yml` | Prometheus and Grafana, both in the host's own network namespace. The comment at the top of the file says why |
| `prometheus/prometheus.yml` | One scrape target: the models service's own loopback port |
| `grafana/provisioning/` | The Prometheus datasource and the dashboard provider, so neither is a manual click that a redeploy forgets |
| `grafana/dashboards/models.json` | The one dashboard: four current counts, three of them also as a week of history |
| `deploy/` | The nginx vhost, the tunnel config and the systemd unit for `grafana.pleion.dev` |
| `tool/deploy.sh` | Syncs this directory to bob and runs `docker compose up -d` |

## Why the metric is a gauge

Every number `/metrics` reports can go down (an account can be deleted, and a
model with it), so none of them carries the `_total` suffix Prometheus
reserves for a count that only ever grows. "How many accounts exist right
now" is a gauge. "How many have ever registered" would need a counter this
service does not keep, because nothing here has needed that answer yet.

## Why storage is deduplicated

A blob is content-addressed and stored once, so two people uploading the same
cube share a file on disk. `flutter3d_models_storage_bytes` sums one row per
distinct hash, the same way `FileBlobStore` put them on disk as one file. It
is not the sum of every model's own `size_bytes`. `MetricsRepository` does
this in SQL (`group by blob_sha256`), and `cloud/server/test/metrics_db_test.dart`
checks that two models sharing a hash count as one blob's worth.

## Deploying

```bash
cloud/monitoring/tool/deploy.sh
```

Rsyncs this directory to `bob:/opt/flutter3d-monitoring` and runs
`docker compose up -d`. A changed dashboard or scrape config needs nothing
more: both are bind-mounted read-only and re-read on their own (Grafana's
file provider polls its directory every 30s). Only a change to
`docker-compose.yml` itself needs the container recreated, and the same
command does that.

### The first time

These steps are done once, by hand, because each one creates something outside
this repository. It is the same shape as the first-time list in
[cloud/README.md](../README.md), for the same reasons.

1. Grafana's admin password. Generate one and put it where the compose file
   reads it from:

   ```bash
   ssh bob "install -m 600 /dev/null /etc/flutter3d-monitoring.env && \
     echo GF_SECURITY_ADMIN_PASSWORD=\$(openssl rand -base64 24) | \
     ssh bob 'tee /etc/flutter3d-monitoring.env > /dev/null'"
   ```

   If a pipe through a second `ssh` is awkward, run the two halves
   separately. What matters is a 600-mode file with one line in it, never in
   this repository.

2. nginx site. Copy `deploy/nginx-grafana.pleion.dev.conf` to
   `/etc/nginx/sites-available/grafana.pleion.dev`, link it into
   `sites-enabled`, and run `nginx -t && systemctl reload nginx`. There is no
   basic auth in front of it. The comment at the top of that file explains
   why a first pass had one and what it broke.

3. Tunnel. Run `cloudflared tunnel create flutter3d-grafana`, put the ID into
   `deploy/cloudflared-grafana.yml` and copy that to
   `/etc/cloudflared/grafana.yml`. Then add the DNS route, naming the config
   and the UUID explicitly. The tunnel step in [cloud/README.md](../README.md)
   says what happens when `--config` is left off. Then enable
   `deploy/cloudflared-grafana.service`.

4. Deploy. Run `cloud/monitoring/tool/deploy.sh`.

### Where it runs

- Containers: `flutter3d-prometheus` and `flutter3d-grafana`, both
  `network_mode: host` on bob, brought up by `docker compose` from
  `/opt/flutter3d-monitoring`
- Prometheus: `127.0.0.1:9091`, scraping `127.0.0.1:8794/metrics`
  directly. ufw admits nothing but SSH, the VPN ports and 80/443/8443, so
  9091 has no route in from outside the machine regardless
- Grafana: `127.0.0.1:3001`, with sign-up and org creation both off
  (`GF_USERS_ALLOW_SIGN_UP`, `GF_USERS_ALLOW_ORG_CREATE`). Its own account
  system is the only gate on this stack
- nginx: `127.0.0.1:8797`, proxying straight through to Grafana
- Tunnel: `cloudflared-grafana.service`

## What is not here

- Alerting. The dashboard is read on demand, and nothing pages anybody when
  storage crosses a threshold. Grafana's own alerting can be provisioned the
  same way the dashboard is, once something needs to send a letter about
  disk space.
- A registrations counter. `flutter3d_models_registered_users` is a
  snapshot, not a running total (see "Why the metric is a gauge" above).
