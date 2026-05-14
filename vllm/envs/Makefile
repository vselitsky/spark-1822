.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c

REMOTE_HOST ?= spark-1822.local
HF_CACHE_HOST ?= /opt/hf/.cache/huggingface

.PHONY: help list cache sync

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "REMOTE_HOST=$(REMOTE_HOST)"
	@echo "HF_CACHE_HOST=$(HF_CACHE_HOST)"

list:  ## List local variants under envs/.
	@ls *.env 2>/dev/null | sed 's/\.env$$//' | sort

cache:  ## List HF repos already downloaded on the remote host's HF cache.
	@ssh $(REMOTE_HOST) 'ls -d $(HF_CACHE_HOST)/hub/models--* 2>/dev/null' \
	    | sed 's|.*/models--||; s|--|/|' | sort

sync:  ## Reconcile envs against the remote HF cache: create new, restore from .bak, orphan to .bak.
	@remote=$$(ssh $(REMOTE_HOST) 'ls -d $(HF_CACHE_HOST)/hub/models--* 2>/dev/null' | sed 's|.*/models--||; s|--|/|'); \
	if [[ -z "$$remote" ]]; then echo "no models on $(REMOTE_HOST):$(HF_CACHE_HOST)/hub/"; exit 0; fi; \
	created=0; restored=0; orphaned=0; \
	while read -r repo; do \
	    [[ -z "$$repo" ]] && continue; \
	    short=$$(echo "$$repo" | cut -d/ -f2 | tr 'A-Z' 'a-z'); \
	    file="$$short.env"; \
	    if grep -lE "^VLLM_MODEL=$$repo[[:space:]]*\$$" *.env 2>/dev/null | head -1 >/dev/null; then \
	        :; \
	    elif [[ -f "$$file.bak" ]] && grep -qE "^VLLM_MODEL=$$repo[[:space:]]*\$$" "$$file.bak"; then \
	        printf '↩ restore %s ← %s.bak\n' "$$file" "$$file"; \
	        mv "$$file.bak" "$$file"; \
	        restored=$$((restored + 1)); \
	    elif [[ -f "$$file" ]]; then \
	        echo "  name clash: $$file already exists but points elsewhere — leave alone, rename manually if needed"; \
	    else \
	        printf '+ create  %s — %s\n' "$$file" "$$repo"; \
	        { \
	            echo "# $$repo · in $(HF_CACHE_HOST) on the remote host."; \
	            echo "# Self-contained — \`make up ENV=$$short\` uses this directly."; \
	            echo ""; \
	            echo "VLLM_TAG=v0.20.2"; \
	            echo "HF_CACHE_HOST=$(HF_CACHE_HOST)"; \
	            echo "HF_TOKEN="; \
	            echo ""; \
	            echo "VLLM_MODEL=$$repo"; \
	            echo "VLLM_SERVED_NAME=$$short"; \
	            echo "VLLM_GPU_MEM=0.9"; \
	            echo "VLLM_MAX_LEN=8192"; \
	        } > "$$file"; \
	        created=$$((created + 1)); \
	    fi; \
	done <<<"$$remote"; \
	for f in *.env; do \
	    [[ -f "$$f" ]] || continue; \
	    repo=$$(grep -E '^VLLM_MODEL=' "$$f" | head -1 | cut -d= -f2-); \
	    [[ -z "$$repo" ]] && continue; \
	    if ! grep -qFx "$$repo" <<<"$$remote"; then \
	        printf '→ orphan  %s → %s.bak\n' "$$f" "$$f"; \
	        mv "$$f" "$$f.bak"; \
	        orphaned=$$((orphaned + 1)); \
	    fi; \
	done; \
	echo "summary — $$created created, $$restored restored, $$orphaned orphaned"
