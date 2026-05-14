# vllm env variants

One **self-contained** file per model. `make up ENV=<name>` invokes `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env` is written. For management afterwards, pass the same `--env-file` to docker compose, or use plain `docker` against the container name.

Each variant here corresponds to a model **already downloaded** on this host (under `/opt/hf/.cache/huggingface/`). Adding a new variant means first `hf download <repo>` (or letting vLLM pull on first start), then dropping a new `<name>.env` here — or run `make hf-sync` (from the parent dir) / `make sync` (here) to do it automatically based on what's in the HF cache.

## Current variants

| File | HF repo |
|---|---|
| `gpt-oss-120b.env` | `openai/gpt-oss-120b` |
| `gpt-oss-20b.env` | `openai/gpt-oss-20b` |
| `qwen3.5-27b-reasoning.env` | `Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled` |
| `qwen3.6-27b.env` | `Qwen/Qwen3.6-27B` |

## What each file sets

- `VLLM_MODEL` — HuggingFace repo ID (vLLM resolves via the standard HF Hub cache).
- `VLLM_SERVED_NAME` — name surfaced via the OpenAI-compatible API.
- `VLLM_GPU_MEM` — fraction of VRAM vLLM may use (0.0–1.0).
- `VLLM_MAX_LEN` — max context length.

Gated models need `HF_TOKEN` set in the variant file (`envs/<name>.env`).

## Picking a variant

```bash
# from /opt/vllm:
make list                                  # show available variants
make up ENV=qwen3.5-27b-reasoning          # docker compose --env-file envs/<name>.env up -d
docker logs -f vllm                        # tail (plain docker — no env needed)
docker compose --env-file envs/qwen3.5-27b-reasoning.env down
```

## Maintenance

This directory has its own `Makefile` for keeping the variant list in sync with what's actually downloaded in this host's HF cache. It is **read-only against the cache** and **never downloads** anything itself — use `hf download <repo>` to populate the cache, then `make sync` to materialize an env file.

```bash
make list       # local variants
make cache      # HF repos already downloaded in $(HF_CACHE)/hub/
make sync       # reconcile envs against the cache:
                #   + create envs for newly cached models
                #   ↩ restore <name>.env from <name>.env.bak when a model returns
                #   → move <name>.env to <name>.env.bak when the model leaves
```

These targets are also exposed at the parent dir as `make hf-cache` / `make hf-sync` for convenience.

`*.env.bak` is gitignored — host-local artifact of the sync's orphaning path. A subsequent `make sync` will restore the file if the corresponding model reappears in the cache, preserving any hand edits you'd made.

## See also

- [`../README.md`](../README.md) for the rest of the stack docs.
