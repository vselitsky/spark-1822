#!/usr/bin/env bash
# llama-server launcher. Picks the model source in this order:
#   1. MODEL_PATH       — local file (Ollama blob, HF snapshot, anything you mount)
#   2. MODEL_URL        — remote URL (llama.cpp downloads + caches it)
# Exactly one of these must be set.

set -euo pipefail

args=(
    --host "${LISTEN_HOST:-0.0.0.0}"
    --port "${LISTEN_PORT:-8080}"
    --ctx-size "${CTX_SIZE:-8192}"
    --n-gpu-layers "${N_GPU_LAYERS:-999}"
    --alias "${MODEL_ALIAS:-llama-cpp}"
)

if [[ -n "${MODEL_PATH:-}" ]]; then
    if [[ ! -e "${MODEL_PATH}" ]]; then
        echo "MODEL_PATH=${MODEL_PATH} does not exist inside the container" >&2
        echo "available roots:" >&2
        echo "  /ollama/models/blobs/                — Ollama-cached GGUF blobs (sha256-named)" >&2
        echo "  /root/.cache/huggingface/hub/        — HuggingFace Hub cache snapshots" >&2
        echo "  /root/.cache/llama.cpp/              — llama.cpp's own download cache" >&2
        exit 1
    fi
    args+=( --model "${MODEL_PATH}" )
elif [[ -n "${MODEL_URL:-}" ]]; then
    args+=( --model-url "${MODEL_URL}" )
else
    echo "set MODEL_PATH or MODEL_URL in .env" >&2
    exit 64
fi

echo "launching: llama-server ${args[*]}"
exec /app/llama-server "${args[@]}"
