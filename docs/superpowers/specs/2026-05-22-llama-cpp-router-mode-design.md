# llama-cpp router mode — design

**Status:** draft, pending implementation.
**Date:** 2026-05-22.
**Service:** `llama-cpp/`.

## Goal

Make every GGUF model already in the host's HuggingFace CLI cache (`/opt/hf/.cache/huggingface/hub/`) reachable through a single `llama-server` endpoint, without picking one model at start-up. The user types a model ID in the API request (or the OpenWebUI dropdown) and the server loads it on demand.

## Background

llama.cpp shipped **router mode** on 2025-12-11 (HF blog: <https://huggingface.co/blog/ggml-org/model-management-in-llamacpp>). When `llama-server` is started without `--model`, it scans `--models-dir` for GGUF files and exposes them via `/v1/models`. Loading is on demand. Up to `--models-max` (default 4) stay resident; LRU evicts the rest. Per-model overrides live in a `config.ini` file passed via `--models-preset`.

This subsumes the current per-variant `envs/*.env` workflow: instead of one env file per model and a stack restart to switch, the running server already knows about every model and switches on request.

### Current state (pre-design)

- `llama-cpp/docker-compose.yml` runs one `llama-server` container, configured for exactly one model via `MODEL_PATH` / `MODEL_OLLAMA` / `MODEL_URL` env vars.
- `llama-cpp/entrypoint.sh` enforces "exactly one model selector must be set" — exits 64 if none.
- `llama-cpp/envs/<name>.env` overlays per-model config (`MODEL_PATH`, `MODEL_ALIAS`, `CTX_SIZE`, `N_GPU_LAYERS`) on top of the host-wide `.env`.
- `make hf-sync` walks the HF cache (`find $(HF_CACHE) -name "*.gguf"`) and auto-generates one `envs/*.env` per GGUF found; restores from `.bak` if a previously-removed GGUF returns; orphans removed ones to `.bak`.
- `make hf-cache` lists what's in the caches.
- Image is pinned by manifest-list digest: `LLAMACPP_TAG=server-cuda@sha256:a04923d…` — predates router mode.
- HF cache bind-mounted at `/root/.cache/huggingface` (read-only). Layout: `hub/models--<org>--<repo>/snapshots/<rev>/<file>.gguf`.
- Ollama blob volume `open-webui-ollama` bind-mounted at `/ollama` (read-only). Blobs are sha-named, no `.gguf` extension.
- Named volume `llama-cpp-cache` for URL-downloaded GGUFs (filled by `MODEL_URL`).
- 4 HF repos in the cache are **safetensors-only** and not loadable by llama.cpp directly: `openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `Qwen/Qwen3.6-27B`, `Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled`.

## Decisions (locked in)

1. **Coexistence first.** Router mode becomes the new default. Classic single-model mode (`MODEL_PATH` / `MODEL_OLLAMA` / `MODEL_URL`) keeps working unchanged. User verifies router mode in production before classic mode is deprecated.
2. **Per-model knobs via auto-generated `config.ini`.** `make hf-sync` writes one `[model]` section per GGUF, with defaults for `ctx-size` and `n-gpu-layers`. Existing per-model tunings (the 120b's `CTX_SIZE=8192`) carry over.
3. **`hf-sync` lifecycle.** During the trial period, `hf-sync` keeps generating per-variant env files **and** the new router artifacts. Once router mode is verified, both classic-mode entrypoint branches and `hf-sync`'s env-file generation are scheduled for removal.
4. **Approach: symlink farm + router.** A flat host directory of symlinks pointing into the HF cache, bind-mounted at `/models` in the container. Router scans the flat dir. (Alternative considered: point `--models-dir` directly at the deeply-nested HF cache — rejected because `--models-dir` is not documented as recursive and the auto-derived model IDs would be the ugly `models--<org>--<repo>--snapshots--<rev>` form.)

## Architecture

```
host                                              container
─────────────────────────────────────────────     ──────────────────────────────────────────
/opt/hf/.cache/huggingface/                  ──►  /root/.cache/huggingface/         (ro)
  hub/models--<org>--<repo>/snapshots/<rev>/        (HF cache, source of truth for blobs)
    <file>.gguf

/opt/hf/.cache/llama-cpp-models/             ──►  /models/                          (ro)
  config.ini                                        (router preset file, generated)
  <file>.gguf ──► /root/.cache/huggingface/         (symlink — resolves in-container)
        hub/.../snapshots/<rev>/<file>.gguf
  …

/opt/llama-cpp/envs/<name>.env               (classic single-model overlay; unchanged)
```

- **Symlink farm** at `${SYMLINK_FARM_HOST:-/opt/hf/.cache/llama-cpp-models}` on host, mounted at `/models` in container (read-only).
- Symlink targets are **container-side absolute paths** (`/root/.cache/huggingface/hub/…`) — they only need to resolve inside the container.
- `config.ini` lives at `<symlink-farm>/config.ini` → `/models/config.ini`.
- Entrypoint decides router vs classic mode based on whether `MODEL_*` env vars are set.

## Detailed design

### `entrypoint.sh`

Today's branching (`MODEL_OLLAMA → MODEL_PATH; require MODEL_PATH or MODEL_URL else exit 64`) gains a router branch:

```
1. (unchanged) Resolve MODEL_OLLAMA → MODEL_PATH if MODEL_OLLAMA set.
2. If MODEL_PATH set        → classic: --model "$MODEL_PATH" --ctx-size --n-gpu-layers --alias
3. Elif MODEL_URL set       → classic: --model-url "$MODEL_URL" --ctx-size --n-gpu-layers --alias
4. Else                     → router (NEW):
                                --models-dir /models
                                --models-preset /models/config.ini
                                --models-max "${MODELS_MAX:-2}"
```

Warnings before `exec` in router mode:

- If `/models` exists but contains zero `*.gguf` (symlinks count): one-line warning pointing at `make hf-sync`.
- If `/models/config.ini` is missing: one-line warning that defaults will be used; `exec` proceeds without `--models-preset`.

`MODEL_ALIAS` becomes dead-code in router mode (router uses section names from `config.ini`); kept available for classic mode.

No top-level `--ctx-size` / `--n-gpu-layers` / `--alias` flags in router mode. Per-model knobs are the sole source of truth via `config.ini`; the HF blog notes that top-level args propagate as defaults and presets override, but doing both creates two sources of truth and obscures where the 120b's 8192 cap actually comes from.

### `docker-compose.yml`

Additions:

```yaml
services:
  llama-cpp:
    environment:
      MODELS_MAX: ${MODELS_MAX:-2}
    volumes:
      - ${SYMLINK_FARM_HOST:-/opt/hf/.cache/llama-cpp-models}:/models:ro
```

Everything else (Traefik labels, GPU reservation, `restart: "no"`, healthcheck, HF cache mount, Ollama mount, `llama-cpp-cache` volume, loopback port bind, security_opt, logging) unchanged.

`healthcheck.start_period: 600s` stays. Router mode boots fast (no model loaded), but classic mode (still supported) needs the long window for the initial download.

### `.env.example`

Add:

```
# Symlink farm host directory — populated by `make hf-sync`; mounted into the
# container at /models (read-only). Router mode scans this directory.
SYMLINK_FARM_HOST=/opt/hf/.cache/llama-cpp-models

# Router mode: max number of models held resident in VRAM at once. LRU evicts
# the rest. Note: the router has no per-model VRAM accounting — set this with
# your largest resident model in mind. See README for the formula.
MODELS_MAX=2
```

Existing `MODEL_PATH=` / `MODEL_URL=` / `MODEL_OLLAMA=` stay blank-by-default, which is what triggers router mode.

### Symlink farm

**Host path:** `${SYMLINK_FARM_HOST:-/opt/hf/.cache/llama-cpp-models}`. Sibling of the HF cache, same filesystem. Owned by whoever runs `make hf-sync`.

**Contents:** one symlink per `*.gguf` found in `$HF_CACHE_HOST/hub/models--*/snapshots/*/`, plus `config.ini`.

**Symlink naming:** bare basename of the GGUF (no path mangling). Preserves the existing names llama.cpp can split-load (e.g. `…-00001-of-00002.gguf` / `…-00002-of-00002.gguf` stay adjacent in `/models`).

**Symlink target:** the **container-side** absolute path, e.g. `/root/.cache/huggingface/hub/models--<org>--<repo>/snapshots/<rev>/<file>.gguf`. Resolves inside the container via the existing HF bind mount.

**Multi-part split GGUFs:** symlink **all parts**. llama.cpp's server only references the first part as the model path, but opens part 2/3/… by naming convention from the same directory.

**Excluded:**

- **Safetensors-only HF repos** — not loadable by llama.cpp. `hf-sync` keeps its existing "note: N HF repo(s) have only safetensors" hint.
- **Ollama blobs** (`/ollama/models/blobs/sha256-<hex>`) — sha-named, no `.gguf` extension, router probing behavior undocumented. Still reachable via classic `MODEL_OLLAMA`.
- **`llama-cpp-cache` named volume** (URL-downloaded GGUFs) — lives in a Docker volume, not a host path; populating symlinks would require a helper container. Out of scope for v1; reachable via classic `MODEL_URL`. May be added later.

**Name collisions:** if two HF repos contain a file with the same basename, `hf-sync` keeps the first encountered and prints a warning naming both repo paths. Not expected in practice (GGUF filenames embed model + quant).

**Atomic regeneration:** `hf-sync` uses `ln -sfn <target> <path>` (atomic replace; the current `hf-sync` uses `ln -s` which would fail on existing names). On orphan, `rm` the symlink. `config.ini` is written to `config.ini.tmp` then `mv`'d into place, so a running `llama-server` reload never sees a half-written file.

### `config.ini`

**Path on host:** `<symlink-farm>/config.ini`. **In container:** `/models/config.ini`.

**Shape:**

```ini
# Auto-generated by `make hf-sync`. Sections are managed:
#   - hf-sync owns the `model` line and the section's existence.
#   - All other keys are user-editable and preserved across `hf-sync` runs.
# Orphaned sections (GGUF no longer in cache) are moved to a comment block
# at the bottom, parallel to the existing envs/*.env.bak mechanism.

[gpt-oss-safeguard-120b]
model = /models/gpt-oss-safeguard-120b-MXFP4-00001-of-00002.gguf
alias = lmstudio-community/gpt-oss-safeguard-120b-GGUF:MXFP4
ctx-size = 8192
n-gpu-layers = 999

[<next-model>]
model = /models/<file>.gguf
alias = <org>/<repo>:<quant>
ctx-size = 8192
n-gpu-layers = 999
```

**Section name:** the short alias derived by the same regex `hf-sync` already uses for env-file naming — strip `.gguf`, strip `-MXFP4*` / `-Q[0-9]*` / `-IQ[0-9]*`, lowercase. Preserves continuity with the existing `MODEL_ALIAS` values and the OpenWebUI/curl examples in the README.

**`alias` line:** HF-style `<org>/<repo>:<quant>` ID, derived from the source HF cache path. Exposed by the router alongside the section-name ID. (Subject to **Open Question 1** below.)

**Default values:** `ctx-size` and `n-gpu-layers` come from the host-wide `.env` (`CTX_SIZE`, `N_GPU_LAYERS`). Override per-section by hand-editing; hf-sync preserves edits.

**Managed-field semantics:** on regeneration, `hf-sync` rewrites only the `model =` line of each section (it owns "where is the GGUF on disk"); leaves all other keys verbatim. Mirrors the kubernetes server-side-apply pattern.

**Orphans:** when a GGUF disappears from the cache, its section is moved to a `# [orphan: <name>]` comment block at the bottom of the file. Restored verbatim if the GGUF reappears (parallel to today's `.bak` round-trip).

### `Makefile`

**`make up`** (no `ENV=`) — start in router mode. Today's `make up` errors with `usage: make up ENV=<name>`; this loosens that: with `ENV=`, classic mode (current behavior); without, router mode (new). Implementation: when `ENV` is empty, skip the `envs/$(ENV).env` overlay and just `$(COMPOSE) --env-file .env up -d`.

**`make hf-sync`** — gains a second pass after today's env-file reconciliation:

1. Use `hf cache scan --format json` (jq-parsed) instead of `find … *.gguf` to enumerate GGUFs in the HF cache. Honors HF's actual cache layout, handles partial downloads / locked snapshots, future-proof against layout changes.
2. For each GGUF: `ln -sfn <container-path> <symlink-farm>/<basename>`.
3. Rebuild `config.ini.tmp` with one section per current GGUF (preserving user-edited keys from any existing `config.ini`), then `mv` into place.
4. Remove symlinks for GGUFs no longer in the cache; move their `config.ini` sections to the orphan comment block.
5. Print summary: `+ symlink / ↩ unchanged / → orphan` counts.

Existing env-file reconciliation pass stays untouched during the trial.

**`make hf-cache`** — annotate each HF repo line with `[router]` if at least one of its GGUFs has a symlink in the farm. Quick visual check that the router will see it.

**`make models`** *(new)* — `curl -s http://127.0.0.1:8080/v1/models | jq .` for a sanity check after `hf-sync`. Errors cleanly if the server isn't running.

### Image tag bump (precondition)

Router mode requires a llama.cpp build from 2025-12-11 or later. Current pin `server-cuda@sha256:a04923d…` predates it.

Re-resolve via the snippet in `llama-cpp/README.md` → "Pinning the image", set the new digest in `.env` and `.env.example`. Spec implementation depends on this; verify with `docker compose up -d` and a one-shot `llama-server --help | grep models-dir` before merging.

## Open questions for user decision

**OQ1 — Model ID convention.** The router exposes whatever the `config.ini` section name is, plus any `alias =` entries. Three options:

- **(a) Section name = short alias, no `alias`.** Today's `MODEL_ALIAS` values become the model IDs. Simple, matches existing OpenWebUI/curl examples. Loses HF-style discoverability.
- **(b) Section name = short alias, `alias =` adds HF-style.** Both work. Default in the design above. Recommended.
- **(c) Section name = HF-style, no alias.** Aligns with vLLM/OpenRouter/SDK conventions but breaks the existing API surface (existing requests with `"model": "gpt-oss-safeguard-120b"` would need updating).

**OQ2 — API auth.** Today `llama-server` runs without `--api-key`. Classic mode: anyone on the LAN can prompt the loaded model. Router mode: anyone on the LAN can also trigger arbitrary cold-loads of any GGUF in the cache, which is a meaningfully higher cost per request (one cold-load can take minutes and exhaust VRAM). Options:

- **(a) Set `--api-key` via new `LLAMA_API_KEY` env var.** Requires updating any internal clients (OpenWebUI, scripts). Clean.
- **(b) Document the trade-off and leave it open.** Status quo. Acceptable on a fully-trusted LAN.

Default in the design: **(b)** — flag in README, no code change. Switch to (a) if you want the lockdown.

**OQ3 — `MODELS_MAX` default.** Set to `2` in this design (down from the upstream default of `4`) because your largest model (gpt-oss-safeguard-120b) is ~65 GiB resident; two simultaneously resident copies of that already saturate the GB10's 124 GiB. Drop to `1` for "behave like classic mode" semantics, raise to `4` if you intend to run mostly smaller models. No correct universal answer — `2` is a defensive default.

## Deprecation path (post-verification)

Once router mode is verified working in production (you've used it for a few days across model switches, OpenWebUI works, `/v1/models` lists everything, no surprises):

1. Remove classic-mode branches from `entrypoint.sh` (steps 2–3). The router becomes the only mode. `MODEL_PATH` / `MODEL_OLLAMA` / `MODEL_URL` env vars become no-ops.
2. Remove env-file generation from `make hf-sync` (the first pass). It only generates router artifacts.
3. Move existing `envs/*.env` to `envs/*.env.bak`, leaving the directory as a historical record. Update `envs/README.md` to point at `config.ini`.
4. Drop `MODEL_OLLAMA` resolution logic and the `/ollama` mount — Ollama blobs are no longer reachable without classic mode. (Or keep the mount and figure out how to surface Ollama blobs to the router; out of scope for this spec.)
5. Update READMEs accordingly.

This is a separate PR, contingent on user sign-off.

## Out of scope

- Surfacing Ollama-cached GGUFs to the router (sha-named, no `.gguf` extension; needs separate symlink-with-rename logic).
- Surfacing URL-downloaded GGUFs in `llama-cpp-cache` to the router (lives in a Docker volume; needs helper-container symlinker).
- Automated safetensors → GGUF conversion (`convert_hf_to_gguf.py`). The 4 safetensors-only repos stay invisible to llama.cpp by design.
- Per-model GPU pinning (the GB10 is single-GPU; not applicable).
- Multi-tenant fairness / quotas. The single-user assumption from the existing stack holds.
- `llama-swap` evaluation. The HF native router subsumes its use case for this deployment.

## Verification plan

Pre-merge (on a feature branch, then on the real host):

1. **Image tag bump verified.** `docker run --rm <new-tag> /app/llama-server --help | grep -E '(models-dir|models-max|models-preset)'` returns the three flags.
2. **Symlink farm builds.** `make hf-sync` produces a `/opt/hf/.cache/llama-cpp-models/` with one symlink per HF-cache GGUF and a non-empty `config.ini`. Manual `ls -l` of the dir matches expectations.
3. **Container starts in router mode.** `make up` (no `ENV=`), `docker compose logs -f llama-cpp` shows `--models-dir /models --models-preset /models/config.ini`, healthcheck goes green.
4. **`/v1/models` lists everything.** `make models` returns one entry per GGUF symlink with status `unloaded`.
5. **On-demand load works.** `curl /v1/chat/completions -d '{"model":"gpt-oss-safeguard-120b", …}'` triggers a load (visible in logs), returns a completion. A second request to a different model evicts the first when `MODELS_MAX` is hit.
6. **Classic mode still works.** `make up ENV=gpt-oss-safeguard-120b-hf` starts in classic mode (no `--models-dir` in logs), the model loads at startup as today.
7. **OpenWebUI dropdown** (if wired): switching model in the UI surfaces the right list and chats route to the right model.
8. **`hf-sync` idempotency.** Run `make hf-sync` twice in a row. Second run prints zero changes. `config.ini` byte-identical between runs (modulo timestamp comments, if any).
9. **`hf-sync` preserves hand-edits.** Manually edit `ctx-size = 32768` in some section, run `make hf-sync`, verify the edit survives.
10. **Atomic writes.** With `llama-server` running router mode, run `make hf-sync` ten times in a tight loop; no spurious 5xx from `/v1/models`.

## Risks

- **`--models-dir` recursion not documented.** Mitigation: the symlink farm is flat by design. Even if a future llama.cpp version recurses, that's only a bonus.
- **`hf cache scan` JSON shape changes.** It's the supported API but it has evolved (e.g., `huggingface-cli scan-cache` → `hf cache scan` rename). Mitigation: pin a known HF CLI version on the host or fall back to `find` if `hf cache scan --format json` fails (the `find` walk that exists today still works as a fallback).
- **VRAM blow-up with several large models.** Mitigation: `MODELS_MAX=2` default, README documents the formula, classic mode is still available as the safe fallback.
- **OpenAI-strict clients choking on extended `/v1/models` JSON.** The router adds fields (`in_cache`, `path`, `status`). Most clients ignore unknown fields, but some validate. Mitigation: spot-check OpenWebUI and any internal scripts; if a client breaks, file an upstream issue or run a trivial passthrough that strips fields.
- **Symlinks pointing at container-side paths.** If anyone tries to `ls -L` the symlink farm **on the host**, it'll show broken links (target paths only exist in the container). This is intentional, but worth documenting in the README so it's not mistaken for a bug.

## Implementation order (rough; for the writing-plans pass)

1. Bump `LLAMACPP_TAG` to a post-2025-12-11 digest; verify the binary has the flags. *(blocking)*
2. Add `SYMLINK_FARM_HOST` mount + `MODELS_MAX` env to `docker-compose.yml`; add to `.env.example`.
3. Add router branch to `entrypoint.sh`. Existing classic branches untouched.
4. Add `make models` target.
5. Loosen `make up` to allow `ENV=` to be empty.
6. Extend `make hf-sync` with the symlink-farm + `config.ini` pass.
7. Update `llama-cpp/README.md` (new section, demote classic to "legacy", update files tree).
8. Update `llama-cpp/envs/README.md` (one-line redirect).
9. Update repo-root `README.md` service description.
10. Manual run through the verification plan on the real host.
