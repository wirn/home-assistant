#!/usr/bin/env bash
# Read-only checks. Run interactively so sudo can request authentication.
set -eu

hostname
docker compose version
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
ls -ld /srv /srv/docker /srv/appdata
for path in /srv/docker/homeassistant /srv/appdata/homeassistant; do
  if [ -e "$path" ] || [ -L "$path" ]; then
    printf 'EXISTING TARGET: %s\n' "$path"
    ls -ld "$path"
  else
    printf 'NEW TARGET: %s\n' "$path"
  fi
done
df -hT /srv /srv/appdata
if mountpoint -q /mnt/external; then
  findmnt --target /mnt/external
  df -hT /mnt/external
else
  printf '/mnt/external is not a mount point; do not use it for backups yet.\n'
fi
ss -lntu
ip -brief address
sudo ufw status verbose
sudo nft list ruleset
