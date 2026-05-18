.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c
.SUFFIXES:
.DELETE_ON_ERROR:

# One VIP service per backend. The DNS name of each is `<svc>.<tailnet>.ts.net`.
# Each must already exist in the Tailscale admin console
# (https://login.tailscale.com/admin/services) with required ports tcp/80 + tcp/443.
SERVICES ?= svc:traefik svc:vllm svc:llama svc:ollama svc:open-webui svc:netdata

CONTAINER ?= tailscale
CONFIG    ?= /config/services.json

.PHONY: help services-apply services-status services-clear

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-20s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Services this Makefile manages (override with SERVICES=...):"
	@echo "  $(SERVICES)"

services-apply:  ## Copy services.json into the tailscale container, set-config + advertise each SERVICE.
	@docker compose cp services.json $(CONTAINER):$(CONFIG)
	@for svc in $(SERVICES); do \
	    echo "→ $$svc"; \
	    docker compose exec $(CONTAINER) tailscale serve set-config --service=$$svc $(CONFIG); \
	    docker compose exec $(CONTAINER) tailscale serve advertise $$svc; \
	done
	@echo
	@echo "Advertised services (from daemon prefs):"
	@docker compose exec $(CONTAINER) tailscale debug prefs | grep -A20 AdvertiseServices

services-status:  ## Show the daemon's view of each service.
	@for svc in $(SERVICES); do \
	    echo "=== $$svc ==="; \
	    docker compose exec $(CONTAINER) tailscale serve get-config --service=$$svc 2>&1 | sed 's/^/  /'; \
	done

services-clear:  ## Drain + clear every SERVICE on this node (stops advertising; remote state in admin console is untouched).
	@for svc in $(SERVICES); do \
	    echo "→ drain $$svc"; \
	    docker compose exec $(CONTAINER) tailscale serve drain $$svc || true; \
	    echo "→ clear $$svc"; \
	    docker compose exec $(CONTAINER) tailscale serve clear $$svc || true; \
	done
