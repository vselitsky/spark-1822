# netdata

Real-time observability agent for the host — CPU, memory, disks, network, every Docker container, plus systemd units and a long list of auto-detected applications. UI is fronted by Caddy at `https://netdata.${CADDY_DOMAIN}` with basic-auth.

## Topology

Netdata runs with `network_mode: host` and `pid: host` so it has full visibility into the host's processes, namespaces, and network interfaces. It listens on `0.0.0.0:19999`. The unauthenticated direct port is reachable on the LAN; the canonical, authenticated access path is `https://netdata.${CADDY_DOMAIN}` (via Caddy). Add a host firewall rule to block external `:19999` if you want stricter isolation.

## Files

```
netdata/
├── docker-compose.yml
├── .env.example         # committed
└── .env                 # gitignored
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   NETDATA_TAG       — pinned image tag
#   NETDATA_HOSTNAME  — what netdata reports as host name
#   DOCKER_GID        — host's docker-group GID (so netdata can read docker.sock)
#                       getent group docker | cut -d: -f3
```

## Basic-auth credentials (Caddy)

Netdata has no built-in auth, so Caddy gates access to `netdata.${CADDY_DOMAIN}` with HTTP basic auth. Generate the bcrypt hash and store it in `caddy/.env`:

```bash
# On the host:
docker exec -it caddy caddy hash-password --plaintext 'YOUR_PASSWORD'
# Copy the printed hash into caddy/.env as NETDATA_BASIC_AUTH_HASH=...
docker compose -f /opt/caddy/docker-compose.yml up -d   # picks up new env
```

To rotate the password, repeat and reload Caddy:

```bash
docker compose -f /opt/caddy/docker-compose.yml exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Deploy

```bash
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:19999/api/v1/info | jq .version
```

Then browse to `https://netdata.${CADDY_DOMAIN}`.

## What it monitors out of the box

- System: CPU, load, RAM, swap, IO, network interfaces, TCP/UDP socket stats, disk space and IO, systemd units, kernel events.
- Docker: every running container's CPU/memory/IO/network (via docker.sock and cgroups).
- Apps: many are auto-detected (Postgres, Redis, NGINX, etc.) when they're running.

## GPU metrics (not yet wired up)

The default agent doesn't expose `nvidia-smi` metrics on the GB10. To add them, bind-mount `/usr/bin/nvidia-smi` (and matching libs) into the container, or run the dedicated [DCGM exporter](https://github.com/NVIDIA/dcgm-exporter) and let Netdata scrape it. Tracked as a follow-up.

## Upgrade

```bash
# Bump NETDATA_TAG in .env, then:
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f netdata
```

## Uninstall

```bash
docker compose down
docker volume rm netdata-config netdata-lib netdata-cache
```

## See also

- Top-level [README](../README.md) for overall layout, conventions, and CI.
- Netdata Docker docs: <https://learn.netdata.cloud/docs/installing/docker>
- Netdata configuration reference: <https://learn.netdata.cloud/docs/configuring/daemon-configuration>
