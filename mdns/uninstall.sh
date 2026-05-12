#!/bin/bash
# Reverse the install of the sparky-mdns-alias script and unit. Idempotent.
# Disables every running alias instance, removes the script + unit, reloads
# systemd. Does NOT touch your DNS, hosts file, or anything else.

set -euo pipefail

unit="sparky-mdns-alias@.service"
bin="/usr/local/bin/sparky-mdns-alias"

# List every active or enabled instance of the template and stop+disable it.
mapfile -t instances < <(
    systemctl list-units --type=service --all --no-legend 'sparky-mdns-alias@*.service' 2>/dev/null \
        | awk '{print $1}' | sed 's/^●\s*//' | sort -u
)

if [[ ${#instances[@]} -gt 0 ]]; then
    echo "stopping + disabling instances:"
    for i in "${instances[@]}"; do
        echo "  $i"
        sudo systemctl disable --now "$i" >/dev/null 2>&1 || true
    done
fi

if [[ -f "/etc/systemd/system/$unit" ]]; then
    echo "removing /etc/systemd/system/$unit"
    sudo rm -f "/etc/systemd/system/$unit"
fi

if [[ -f "$bin" ]]; then
    echo "removing $bin"
    sudo rm -f "$bin"
fi

sudo systemctl daemon-reload
sudo systemctl reset-failed 'sparky-mdns-alias@*' 2>/dev/null || true

echo
echo "uninstalled. /opt/mdns/ source files are kept; re-run ./install.sh to reinstall."
