# llama-cpp env variants

One file per model. Picked at start via `--env-file` so `.env` stays put for common settings (image tag, HF cache, HF token).

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
make up VARIANT=gpt-oss-safeguard-120b-hf       # start with that one
make logs                                       # tail
make down
```

Behind the scenes:

```bash
docker compose --env-file .env --env-file envs/<variant>.env up -d
```

## Maintenance

This directory has its own `Makefile` for keeping the variant list in sync with what's actually on the remote host. It is **read-only against the remote** and **never downloads** anything.

```bash
make list       # local variants
make remote     # GGUF files on the remote (llama-cpp-cache volume + HF cache)
make sync       # create an env file for every remote GGUF not yet present (never overwrites)
make stale      # local envs whose MODEL_PATH file isn't on the remote
```

Override host with `REMOTE_HOST=other.local make sync` if you ever need to.

`stale` only validates `MODEL_PATH=` entries (it can check the file exists). `MODEL_URL=` and `MODEL_OLLAMA=` forms aren't validated.

## See also

- [`../README.md`](../README.md) for the rest of the stack docs.
