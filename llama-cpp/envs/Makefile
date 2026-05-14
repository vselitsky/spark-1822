.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c

REMOTE_HOST ?= spark-1822.local
HF_CACHE_HOST ?= /opt/hf/.cache/huggingface
LLAMACPP_CACHE_VOL ?= llama-cpp-cache
LLAMACPP_TAG_DEFAULT ?= server-cuda

.PHONY: help list cache sync

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "REMOTE_HOST=$(REMOTE_HOST)"
	@echo "HF_CACHE_HOST=$(HF_CACHE_HOST)"
	@echo "LLAMACPP_CACHE_VOL=$(LLAMACPP_CACHE_VOL)"

list:  ## List local variants under envs/.
	@ls *.env 2>/dev/null | sed 's/\.env$$//' | sort

cache:  ## Show GGUF files already on the remote host (llama-cpp-cache vol + HF cache).
	@echo "# in docker volume $(LLAMACPP_CACHE_VOL):"
	@ssh $(REMOTE_HOST) "docker run --rm -v $(LLAMACPP_CACHE_VOL):/d alpine sh -c 'ls /d/*.gguf 2>/dev/null'" \
	    | sed 's|.*/||; s|^|  |' || true
	@echo "# in $(HF_CACHE_HOST):"
	@ssh $(REMOTE_HOST) 'find $(HF_CACHE_HOST) -name "*.gguf" 2>/dev/null' \
	    | sed 's|^|  |' || true

sync:  ## Reconcile envs against the remote GGUF inventory: create new, restore from .bak, orphan to .bak.
	@gguf_vol=$$(ssh $(REMOTE_HOST) "docker run --rm -v $(LLAMACPP_CACHE_VOL):/d alpine sh -c 'ls /d/*.gguf 2>/dev/null'" | sed 's|.*/||' | sort -u); \
	gguf_hf=$$(ssh $(REMOTE_HOST) 'find $(HF_CACHE_HOST) -name "*.gguf" 2>/dev/null' | sort -u); \
	created=0; restored=0; orphaned=0; \
	for gguf in $$gguf_vol; do \
	    short=$$(echo "$$gguf" | sed -e 's/\.gguf$$//' -e 's/-MXFP4.*//' -e 's/-Q[0-9].*//' -e 's/-IQ[0-9].*//' | tr 'A-Z' 'a-z'); \
	    file="$$short-hf.env"; \
	    in_container="/root/.cache/llama.cpp/$$gguf"; \
	    if grep -lE "^MODEL_(PATH|URL)=.*$$gguf" *.env 2>/dev/null | head -1 >/dev/null; then \
	        :; \
	    elif [[ -f "$$file.bak" ]] && grep -qE "^MODEL_(PATH|URL)=.*$$gguf" "$$file.bak"; then \
	        printf '↩ restore %s ← %s.bak\n' "$$file" "$$file"; \
	        mv "$$file.bak" "$$file"; \
	        restored=$$((restored + 1)); \
	    elif [[ -f "$$file" ]]; then \
	        echo "  name clash: $$file already exists but points elsewhere — leave alone, rename manually if needed"; \
	    else \
	        printf '+ create  %s — MODEL_PATH=%s\n' "$$file" "$$in_container"; \
	        { \
	            echo "# $$gguf · in docker volume $(LLAMACPP_CACHE_VOL) on the remote host."; \
	            echo "# Self-contained — \`make up ENV=$$short-hf\` uses this directly."; \
	            echo ""; \
	            echo "LLAMACPP_TAG=$(LLAMACPP_TAG_DEFAULT)"; \
	            echo "HF_CACHE_HOST=$(HF_CACHE_HOST)"; \
	            echo "HF_TOKEN="; \
	            echo ""; \
	            echo "MODEL_PATH=$$in_container"; \
	            echo "MODEL_ALIAS=$$short"; \
	            echo "CTX_SIZE=8192"; \
	            echo "N_GPU_LAYERS=999"; \
	        } > "$$file"; \
	        created=$$((created + 1)); \
	    fi; \
	done; \
	for fp in $$gguf_hf; do \
	    base=$$(basename "$$fp"); \
	    short=$$(echo "$$base" | sed -e 's/\.gguf$$//' -e 's/-MXFP4.*//' -e 's/-Q[0-9].*//' -e 's/-IQ[0-9].*//' | tr 'A-Z' 'a-z'); \
	    file="$$short-hfcache.env"; \
	    in_container=$$(echo "$$fp" | sed 's|^$(HF_CACHE_HOST)|/root/.cache/huggingface|'); \
	    if grep -lE "^MODEL_PATH=.*$$base" *.env 2>/dev/null | head -1 >/dev/null; then \
	        :; \
	    elif [[ -f "$$file.bak" ]] && grep -qE "^MODEL_PATH=.*$$base" "$$file.bak"; then \
	        printf '↩ restore %s ← %s.bak\n' "$$file" "$$file"; \
	        mv "$$file.bak" "$$file"; \
	        restored=$$((restored + 1)); \
	    elif [[ -f "$$file" ]]; then \
	        echo "  name clash: $$file already exists but points elsewhere"; \
	    else \
	        printf '+ create  %s — MODEL_PATH=%s\n' "$$file" "$$in_container"; \
	        { \
	            echo "# $$base · in $(HF_CACHE_HOST) on the remote host."; \
	            echo "# Self-contained — \`make up ENV=$$short-hfcache\` uses this directly."; \
	            echo ""; \
	            echo "LLAMACPP_TAG=$(LLAMACPP_TAG_DEFAULT)"; \
	            echo "HF_CACHE_HOST=$(HF_CACHE_HOST)"; \
	            echo "HF_TOKEN="; \
	            echo ""; \
	            echo "MODEL_PATH=$$in_container"; \
	            echo "MODEL_ALIAS=$$short"; \
	            echo "CTX_SIZE=8192"; \
	            echo "N_GPU_LAYERS=999"; \
	        } > "$$file"; \
	        created=$$((created + 1)); \
	    fi; \
	done; \
	for f in *.env; do \
	    [[ -f "$$f" ]] || continue; \
	    p=$$(grep -E '^MODEL_PATH=' "$$f" | head -1 | cut -d= -f2-); \
	    [[ -z "$$p" ]] && continue; \
	    case "$$p" in \
	        /root/.cache/llama.cpp/*) \
	            name=$$(basename "$$p"); \
	            if ! grep -qFx "$$name" <<<"$$gguf_vol"; then \
	                printf '→ orphan  %s → %s.bak\n' "$$f" "$$f"; \
	                mv "$$f" "$$f.bak"; \
	                orphaned=$$((orphaned + 1)); \
	            fi;; \
	        /root/.cache/huggingface/*) \
	            host_path=$$(echo "$$p" | sed 's|^/root/.cache/huggingface|$(HF_CACHE_HOST)|'); \
	            if ! grep -qFx "$$host_path" <<<"$$gguf_hf"; then \
	                printf '→ orphan  %s → %s.bak\n' "$$f" "$$f"; \
	                mv "$$f" "$$f.bak"; \
	                orphaned=$$((orphaned + 1)); \
	            fi;; \
	    esac; \
	done; \
	echo "summary — $$created created, $$restored restored, $$orphaned orphaned"
