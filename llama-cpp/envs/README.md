# llama-cpp env variants

One file per model. Picked at start via `--env-file` so `.env` stays put for common settings (image tag, HF cache, HF token). Add a variant by dropping a new `<name>.env` here; remove one the same way.

## What each file sets

A variant chooses **how to find the model**:

- `MODEL_OLLAMA=<name>:<tag>` — point at an Ollama-cached blob; resolved against the mounted `/ollama` manifest store at start. Portable across hosts as long as the host has the same Ollama model pulled.
- `MODEL_URL=<https://…>` — remote download (cached in the `llama-cpp-cache` Docker volume thereafter).
- `MODEL_PATH=<absolute path inside the container>` — last resort for files at non-standard locations.

Plus `MODEL_ALIAS`, `CTX_SIZE`, and `N_GPU_LAYERS` tuned per model.

## Picking a variant

```bash
# from /opt/llama-cpp:
make list                              # show available variants
make up VARIANT=gpt-oss-safeguard-20b   # start with that one
make logs                              # tail
make down
```

Behind the scenes:

```bash
docker compose --env-file .env --env-file envs/<variant>.env up -d
```

## See also

- [`../README.md`](../README.md) for the rest of the stack docs.
