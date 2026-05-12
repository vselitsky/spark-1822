# llama-cpp

[llama.cpp](https://github.com/ggml-org/llama.cpp) inference server, GPU-accelerated on the GB10 via CUDA. Serves an [OpenAI-compatible API](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) and a small web UI at `https://llama.${CADDY_DOMAIN}` (fronted by [`caddy/`](../caddy/)).

Set up as the workaround for Ollama not being able to pull `gpt-oss-safeguard:120b` (upstream issue: ollama/ollama#16121).

## Topology

`llama-cpp` runs as a single container on the shared `web` Docker network. It connects only to Caddy; no host port is published. The container downloads model files from HuggingFace on first start via the `-hf` flag and caches them in the `llama-cpp-cache` named volume across restarts.

## Files

```
llama-cpp/
├── docker-compose.yml
├── .env.example
└── .env                 # gitignored
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   LLAMACPP_TAG     — pinned image (server-cuda@sha256:...). Multi-arch; works on aarch64+CUDA.
#   MODEL_HF_REPO    — HuggingFace repo, e.g. lmstudio-community/gpt-oss-safeguard-120b-GGUF
#   MODEL_HF_FILE    — GGUF file inside the repo (use the first split for multi-part models)
#   MODEL_ALIAS      — name surfaced via the API
#   CTX_SIZE         — context window (default 8192)
#   N_GPU_LAYERS     — layers on GPU (999 = all)
#   HF_TOKEN         — only needed for gated/private models
```

### Pinning the image

The arm64 + CUDA build is published only under the floating `server-cuda` tag. To pin to a specific build by content digest of the multi-arch manifest list:

```bash
TOK=$(curl -s 'https://ghcr.io/token?service=ghcr.io&scope=repository:ggml-org/llama.cpp:pull' | jq -r .token)
curl -sI -H "Authorization: Bearer $TOK" \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    'https://ghcr.io/v2/ggml-org/llama.cpp/manifests/server-cuda' \
    | grep -i docker-content-digest
```

Set `LLAMACPP_TAG=server-cuda@<that-digest>` in `.env`.

## Deploy

Prereq: `caddy/` is running and the shared `web` network exists.

```bash
docker compose up -d
docker compose logs -f llama-cpp   # first run: HF download (can be many GB / minutes)
```

Once healthy, the server is at `https://llama.${CADDY_DOMAIN}`:

- Web UI — open in browser.
- OpenAI-compatible API:
  ```bash
  curl -k https://llama.spark-1822.local/v1/models
  curl -k https://llama.spark-1822.local/v1/chat/completions \
      -H 'Content-Type: application/json' \
      -d '{"model":"gpt-oss-safeguard-120b","messages":[{"role":"user","content":"hello"}]}'
  ```

## Changing the model

Edit `MODEL_HF_REPO` / `MODEL_HF_FILE` / `MODEL_ALIAS` in `.env`, then:

```bash
docker compose up -d
```

The cache volume preserves previously-downloaded files, so swapping back is fast.

## Upgrade

Resolve the current `server-cuda` digest (snippet above), bump `LLAMACPP_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f llama-cpp
```

## Uninstall

```bash
docker compose down
docker volume rm llama-cpp-cache   # destroys cached model downloads
```

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — reverse proxy in front of this server
- llama.cpp server: <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
- Compute capability 12.1 on GB10 is supported by the upstream image — confirmed with `ggml_cuda_init: found 1 CUDA devices`.
