# tailscale

[Tailscale](https://tailscale.com/) sidecar that registers this host as a node on your tailnet and runs [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) to terminate TLS on tailnet `:443` and reverse-proxy all traffic to `http://traefik:80`. Every backend Traefik already routes becomes reachable over the tailnet without opening any host port.

Based on Tailscale's [Connect a Docker container](https://tailscale.com/docs/features/containers/docker/how-to/connect-docker-container) guide, adapted to this repo's conventions (pinned image tag in `.env`, named state volume, traefik network).

## Files

```
tailscale/
├── docker-compose.yml          # tailscale sidecar, joined to the traefik network, Serve config mounted
├── serve.json                  # Tailscale Serve config — TLS on :443, proxy / → http://traefik:80
├── .env.example                # committed; copy to .env and fill in
└── .env                        # not committed (gitignored)
```

## Configure

### 1. Mint an auth key

Tailscale admin console → **Settings → Keys → Generate auth key**. Recommended:

- **Reusable** — yes (re-creating the container doesn't burn the key)
- **Ephemeral** — no (node state persists across restarts)
- **Pre-approved** — yes (skip manual approval)
- **Tags** — e.g. `tag:server` (matches your ACL policy)

### 2. Drop secrets into `.env`

```bash
cp .env.example .env
# Edit .env:
#   TAILSCALE_TAG  — pin the image (see hub.docker.com/r/tailscale/tailscale/tags)
#   TS_AUTHKEY     — the key from step 1
#   TS_HOSTNAME    — tailnet hostname (default: spark-1822)
```

## Deploy

Prereq: the shared `traefik` Docker network exists. (Bring `traefik/` up at least once, or `docker network create traefik --attachable`.)

```bash
docker compose up -d
docker compose logs -f tailscale    # confirm "Success." and the node URL
```

The node appears in the admin console under **Machines**. MagicDNS publishes it at `https://<TS_HOSTNAME>.<tailnet>.ts.net` — any tailnet-connected device can reach it. TLS uses Tailscale's auto-provisioned MagicDNS cert; no client-side root install needed.

## How it works

```
tailnet client  ──(https, MagicDNS cert)──>  tailscale (:443 on tailnet)
                                                  │
                                                  │ TS_SERVE_CONFIG → Serve handler
                                                  ▼
                                            http://traefik:80   (on the `traefik` docker network)
                                                  │
                                                  │ Host header routing
                                                  ▼
                                              backend (vllm / open-webui / netdata / ...)
```

- The Tailscale daemon runs in userspace mode (no `/dev/net/tun`, no privileged caps) and registers as one node on your tailnet using `TS_AUTHKEY`.
- [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) is configured via the mounted `serve.json`. The container substitutes `${TS_CERT_DOMAIN}` with the node's MagicDNS hostname at startup, then terminates TLS on `:443` with a real publicly-trusted cert.
- All decrypted HTTP is forwarded to `http://traefik:80`. Traefik routes by `Host` header to whichever backend matches.
- State (node key, machine identity) lives in a named docker volume `tailscale-state`, not under `/opt` — so the host's git working tree stays free of secrets.

### Host-header routing — applied

Tailscale Serve forwards requests with the **original** Host header — i.e. `spark-1822.cuscus-macaroni.ts.net`. Out of the box, Traefik's routers match only on `*.spark-1822.local` (the mDNS LAN names), so hitting the tailnet URL would 404.

Fix applied: every existing router has the tailnet hostname appended to its `rule=` clause via `|| Host(\`spark-1822.cuscus-macaroni.ts.net\`)`. Six routers in total — `ollama`, `open-webui`, `vllm`, `llama` (label-based in each app's compose), plus `netdata` and `traefik` (file-based in `traefik/dynamic/services.yml`).

```yaml
# example, open-webui/docker-compose.yml
- "traefik.http.routers.open-webui.rule=Host(`open-webui.spark-1822.local`) || Host(`spark-1822.cuscus-macaroni.ts.net`)"
```

Consequence: a single node has one tailnet hostname, so all six routers now match the *same* tailnet Host. Traefik resolves the conflict by router priority, which defaults to **rule length** — longest rule wins. With the current rules, `open-webui` (longest subdomain prefix) wins, so `https://spark-1822.cuscus-macaroni.ts.net/` lands on Open WebUI. The other five services remain reachable only via their LAN mDNS URLs.

If a different service should be the tailnet default, override priority on its router — either `traefik.http.routers.<name>.priority=1000` as a label, or `priority: 1000` in `dynamic/services.yml`. Higher number wins.

For per-backend tailnet URLs (e.g. `vllm.<tailnet>.ts.net`), see [Tailscale's HTTPS subdomains](https://tailscale.com/kb/1153/enabling-https) — separate setup, not in scope here.

## Logs

```bash
docker compose logs -f tailscale
```

The "Success." line confirms the node is logged in. `tailscale status` inside the container shows peers:

```bash
docker exec tailscale tailscale status
```

## Upgrade

Bump `TAILSCALE_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Uninstall

```bash
docker compose down
docker volume rm tailscale-state    # also discard the node key + machine state
```

Then delete the node from the Tailscale admin console under **Machines** if you're not reusing it.

## Hardening / industry-standard follow-ups

What's shipped is the minimum that works. Four deferred items move this from "homelab-grade" to what Tailscale's own production guides recommend. Each is independently applicable.

### 1. Auth secret via file mount (not env var)

Today `TS_AUTHKEY` is read from `.env` and exposed in the container's environment — visible to anyone who can `docker inspect` the container. Tailscale's `containerboot` supports a file indirection that keeps the secret off the process env: set `TS_AUTHKEY=file:/run/secrets/ts_authkey` (or `TS_AUTHKEY_FILE=/run/secrets/ts_authkey`) and mount the file via a compose `secrets:` block.

Migration sketch (base `docker-compose.yml`):

```yaml
services:
  tailscale:
    environment:
      - TS_AUTHKEY=file:/run/secrets/ts_authkey   # was: TS_AUTHKEY=${TS_AUTHKEY:?…}
    secrets:
      - ts_authkey

secrets:
  ts_authkey:
    file: ./ts_authkey                            # host-local file, mode 0600, gitignored
```

Tradeoff: one extra file on disk to manage (and rotate). Same threat model as `.env` in practice on this single-host setup, but it's the conventional pattern.

### 2. OAuth client credentials instead of a static auth key

Auth keys are accepted but discouraged for persistent nodes — they expire (90-day max), and rotation is manual toil. The recommended pattern for long-running infrastructure is OAuth client credentials: mint an OAuth client in the admin console (**Settings → OAuth clients**), give it the `devices:write` scope and the `tag:server` tag, and use the resulting `tskey-client-...` token. `containerboot` exchanges it for an ephemeral auth key on every restart — no rotation needed.

```bash
# .env
TS_AUTHKEY=tskey-client-XXXXX-OAUTH-SECRET?preauthorized=true&ephemeral=false
```

Tradeoff: one-time setup cost in the dashboard. Bigger lift than (1) — this is a real provisioning decision, not just a refactor.

### 3. Advertise an ACL tag

Without `--advertise-tags`, this node inherits the *minting user's* identity in the Tailscale ACL graph. That works, but it means ACL rules can't distinguish "Dmitry's laptop" from "the inference server" — every device under the same user is treated the same.

Idiomatic fix:

```bash
# .env
TS_EXTRA_ARGS=--advertise-tags=tag:server
```

And in the tailnet ACL JSON:

```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"]
  }
}
```

Required if you later want rules like *"only `tag:client` may reach `tag:server:443`"*. OAuth clients (option 2) typically mint pre-tagged keys, so this combines naturally with (2).

### 4. Kernel networking mode

The base file runs in userspace mode (`TS_USERSPACE=true`). Works without elevated privileges, but every packet goes through a userspace TCP stack — meaningful throughput penalty on a busy node. For an inference host fronting LLM endpoints, kernel mode is the production setting.

```yaml
# docker-compose.yml diff
services:
  tailscale:
    environment:
      - TS_USERSPACE=false      # was: true
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
      - net_raw
```

Tradeoff: requires `/dev/net/tun` on the host (true on stock Ubuntu) and the two capabilities. Required to use this node as a subnet router or exit node, which userspace mode can't do either way.

### Priority

Recommended baseline: **1 + 3 + 4** as a single hardening pass. **2 (OAuth)** is the biggest improvement but it's a provisioning decision, not a config refactor — promote it whenever the next auth key would otherwise need renewing.

## See also

- Top-level [README](../README.md)
- [`traefik/`](../traefik/) — the proxy this sidecar fronts
- [`cloudflare/`](../cloudflare/) — the other edge-ingress stack in this repo, structurally analogous (also tunnels into traefik over an outbound-only connection)
- Tailscale Docker guide: <https://tailscale.com/docs/features/containers/docker/how-to/connect-docker-container>
- Tailscale Serve docs: <https://tailscale.com/kb/1242/tailscale-serve>
- Tailscale OAuth clients: <https://tailscale.com/kb/1215/oauth-clients>
- Tailscale ACL tags: <https://tailscale.com/kb/1068/acl-tags>
