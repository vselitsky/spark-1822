.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c
.SUFFIXES:
.DELETE_ON_ERROR:

ENV ?=
ENV := $(strip $(ENV))
SERVICE := llama-cpp
COMPOSE := docker compose -f docker-compose.yml

.PHONY: help list up hf-cache hf-sync

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Usage:"
	@echo "  make list                       — show available env variants"
	@echo "  make up ENV=<name>              — start $(SERVICE) with that env"
	@echo
	@echo "HF/GGUF-cache maintenance (forwards to envs/Makefile):"
	@echo "  make hf-cache                   — list GGUF files in this host's caches (llama-cpp-cache + HF cache)"
	@echo "  make hf-sync                    — reconcile envs against the caches (create / restore / orphan to .bak)"
	@echo
	@echo "For management, invoke docker compose directly. The compose file"
	@echo "uses required vars (e.g. \$${LLAMACPP_TAG:?...}), so pass --env-file:"
	@echo "  docker compose --env-file envs/<name>.env logs -f $(SERVICE)"
	@echo "  docker compose --env-file envs/<name>.env ps"
	@echo "  docker compose --env-file envs/<name>.env down"
	@echo
	@echo "Or use plain docker against the container name (no env needed):"
	@echo "  docker logs -f $(SERVICE)"
	@echo "  docker stop $(SERVICE)"

list:  ## List available env variants under envs/.
	@ls envs/*.env 2>/dev/null | sed 's|envs/||; s|\.env$$||' | sort

up:  ## Start with the given variant. No .env is written. Usage: make up ENV=<name>
	@if [[ -z "$(ENV)" ]]; then \
	    echo "usage: make up ENV=<name>" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 64; \
	fi
	@if [[ ! -f "envs/$(ENV).env" ]]; then \
	    echo "variant not found: envs/$(ENV).env" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 1; \
	fi
	$(COMPOSE) --env-file "envs/$(ENV).env" up -d

hf-cache:  ## List GGUF files in this host's caches (llama-cpp-cache + HF cache).
	@$(MAKE) -C envs --no-print-directory cache

hf-sync:  ## Reconcile envs against this host's GGUF inventory (create / restore from .bak / orphan to .bak).
	@$(MAKE) -C envs --no-print-directory sync
