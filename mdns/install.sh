#!/bin/bash
# Install the sparky-mdns-alias script + systemd template unit.
# Idempotent — safe to re-run after edits.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

sudo install -m 755 "$here/sparky-mdns-alias"           /usr/local/bin/sparky-mdns-alias
sudo install -m 644 "$here/sparky-mdns-alias@.service"  /etc/systemd/system/sparky-mdns-alias@.service
sudo systemctl daemon-reload

echo
echo "installed. enable an alias instance with:"
echo "  sudo systemctl enable --now 'sparky-mdns-alias@<name>.<host>.local'"
echo
echo "e.g.:"
echo "  sudo systemctl enable --now 'sparky-mdns-alias@netdata.spark-1822.local'"
