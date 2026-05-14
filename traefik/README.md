# traefik

HTTPS reverse proxy — **primary** front-facing entry point on this host. [`caddy/`](../caddy/) is the backup. Caddy and Traefik can't run at the same time (both want host ports `:80` / `:443`); start one or the other.

## How routing works

Each app's `docker-compose.yml` carries `traefik.*` labels (`Host(...)`, `entryPoints`, `tls`, `loadbalancer.server.port`). Traefik's **docker provider** discovers them via the docker socket and wires up routers + services automatically — no central config file to edit when you add a new app. Anything that can't be label-driven (host-network containers like `netdata`; Traefik's own dashboard) lives in `dynamic/services.yml` and the **file provider** picks it up.

Caddy reads `Caddyfile.d/*.caddyfile`, not labels — so the same compose files work under either proxy. Switching is a `docker compose down` + `docker compose up -d` away.

## Files

```
traefik/
├── docker-compose.yml         # traefik service, joins external `caddy` network, mounts docker.sock:ro
├── traefik.yml                # static config — docker + file providers, entrypoints, api, log
├── dynamic/                   # file provider — hot-reloaded on edit
│   ├── services.yml           # routes for things the docker provider can't reach (netdata, dashboard)
│   └── tls.yml                # references the wildcard cert from certs/
├── wildcard.cnf               # OpenSSL config for `make wildcard-cert`
├── Makefile                   # `make wildcard-cert` (mint/renew the leaf)
├── certs/                     # gitignored — wildcard.crt + wildcard.key live here
├── .env.example               # committed; copy to .env and customize
└── .env                       # not committed (gitignored)
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   TRAEFIK_TAG — Traefik image tag (e.g. v3.3)
```

## Mint the TLS wildcard

Traefik serves a single wildcard cert (`*.spark-1822.local` + `spark-1822.local`) **signed by Caddy's existing root CA**. Any client that already trusts `caddy-root.crt` (see [`caddy/README.md`](../caddy/README.md)) automatically trusts Traefik's leaf too — no new CA install needed.

Prereq: Caddy has come up at least once on this host (the root CA lives in the persistent `caddy-data` Docker volume).

```bash
sudo make wildcard-cert
```

Re-run whenever the cert is about to expire (365-day default, override via `CERT_DAYS=30 sudo make wildcard-cert`).

## Deploy

Prereq: the shared `caddy` Docker network must exist. The `caddy/` stack defines it — bring `caddy/` up at least once if you've never started it. Then **stop Caddy** (you can't bind `:80` / `:443` from two stacks at once):

```bash
docker compose -f /opt/caddy/docker-compose.yml down
cd /opt/traefik && docker compose up -d
docker compose ps
```

To switch back to Caddy:

```bash
docker compose -f /opt/traefik/docker-compose.yml down
cd /opt/caddy && docker compose up -d
```

## What gets routed

All hosts use the wildcard cert; routes mirror Caddy's:

| Host | Upstream |
|---|---|
| `https://llama.spark-1822.local` | `llama-cpp:8080` |
| `https://vllm.spark-1822.local` | `vllm:8000` |
| `https://ollama.spark-1822.local` | `ollama:11434` |
| `https://open-webui.spark-1822.local` | `open-webui:8080` |
| `https://netdata.spark-1822.local` | `host.docker.internal:19999` |
| `https://traefik.spark-1822.local` | Traefik's own dashboard + API |

Plain HTTP requests on `:80` are 308-redirected to HTTPS.

## Add an app

For a container on the `caddy` Docker network, just add labels to its `docker-compose.yml` and let the docker provider pick it up:

```yaml
services:
  myapp:
    # … usual config …
    networks:
      - caddy
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=caddy"
      - "traefik.http.routers.myapp.rule=Host(`myapp.spark-1822.local`)"
      - "traefik.http.routers.myapp.entryPoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

Publish the mDNS alias on the host (see [`../mdns/`](../mdns/)):

```bash
cd /opt/mdns && make add ALIAS=myapp
```

Bring the app up — Traefik picks up the labels live (docker provider has `watch: true`); no Traefik restart needed.

For containers that **can't** be label-discovered (host-network mode, external services), drop a router + service into `dynamic/services.yml` instead. The file provider has `watch: true` too.

## Logs

```bash
docker compose logs -f traefik
```

Access logs are emitted as structured JSON via Traefik's `accessLog` directive in `traefik.yml`.

## Upgrade

Bump `TRAEFIK_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Uninstall

```bash
docker compose down
docker volume rm traefik-certs 2>/dev/null || true
```

`certs/wildcard.{crt,key}` on disk persist until you `rm` them manually.

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — the canonical / default reverse proxy
- [`mdns/`](../mdns/) — host-side mDNS aliases
- Traefik docs: <https://doc.traefik.io/traefik/>
