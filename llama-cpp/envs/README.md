# llama-cpp env variants

One **self-contained** file per model. `make up ENV=<name>` invokes `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env` is written. For management afterwards, pass the same `--env-file` to docker compose, or use plain `docker` against the container name.

Each variant chooses **how to find the model**:

- `MODEL_PATH=<absolute path inside the container>` — point at any mounted file (e.g. `/root/.cache/huggingface/hub/.../<file>.gguf`, or an Ollama blob under `/ollama/models/blobs/`).
- `MODEL_OLLAMA=<name>:<tag>` — point at an Ollama-cached blob by name; resolved against the mounted `/ollama` manifest store at start (no hardcoded digests).
- `MODEL_URL=<https://…>` — remote download, cached in the `llama-cpp-cache` Docker volume thereafter.

Plus `MODEL_ALIAS`, `CTX_SIZE`, and `N_GPU_LAYERS` tuned per model.

## Current variants

| File | Source |
|---|---|
| `gpt-oss-safeguard-120b-hf.env` | `MODEL_URL` → `lmstudio-community/gpt-oss-safeguard-120b-GGUF` (already in `llama-cpp-cache`, ~59 GiB) |

## Picking a variant

```bash
# from /opt/llama-cpp:
make list                                       # show available variants
make up ENV=gpt-oss-safeguard-120b-hf           # docker compose --env-file envs/<name>.env up -d
docker logs -f llama-cpp                        # tail (plain docker — no env needed)
docker compose --env-file envs/gpt-oss-safeguard-120b-hf.env down
```

## Maintenance

This directory has its own `Makefile` for keeping the variant list in sync with what's actually on the remote host. It is **read-only against the remote** and **never downloads** anything.

```bash
make list       # local variants
make cache      # GGUF files on the remote (llama-cpp-cache volume + HF cache)
make sync       # reconcile envs against the remote:
                #   + create envs for new remote GGUFs (one per cache location)
                #   ↩ restore <name>.env from <name>.env.bak when the GGUF returns
                #   → move <name>.env to <name>.env.bak when its GGUF leaves
```

These targets are also exposed at the parent dir as `make hf-cache` / `make hf-sync` for convenience. Override the remote host with `REMOTE_HOST=other.local make sync` if you ever need to.

`sync` only orphans envs whose `MODEL_PATH=` points at a GGUF file (it can check existence on the remote). `MODEL_URL=` and `MODEL_OLLAMA=` envs are not validated and are never orphaned automatically — leave them alone or remove them manually.

`*.env.bak` is gitignored — host-local artifact of the sync's orphaning path. A subsequent `make sync` will restore the file if the corresponding GGUF reappears in the remote cache, preserving any hand edits you'd made.

## See also

- [`../README.md`](../README.md) for the rest of the stack docs.
