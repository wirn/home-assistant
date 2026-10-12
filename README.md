# Home Assistant

Home Assistant Container managed with Docker Compose on an existing Ubuntu home server.

Repository: https://github.com/wirn/home-assistant

Status: deployment configuration prepared; server preflight, deployment and health verification pending.

## Layout

- This repository contains Compose, documentation and read-only inspection scripts.
- Server deployment checkout: `/srv/docker/homeassistant`.
- Persistent configuration and runtime data: `/srv/appdata/homeassistant`, mounted at `/config`.
- Deployment image setting: `/srv/docker/homeassistant/.env`, copied from `.env.example`.
- Backups: a separately verified location outside the checkout and runtime directory, with an off-server copy.

Never commit runtime data, `.storage`, integration credentials, databases or backups. The GitHub repository is public. Do not copy the server's configuration directory into the checkout. `secrets.yaml` belongs in the persistent configuration directory. UI-managed credentials are also stored in `.storage`; protecting only `secrets.yaml` is insufficient.

## Architecture

The official image is pinned to `2026.10.1` for reproducible deployment. Updates are manual. The service uses host networking for LAN discovery, restarts unless explicitly stopped, and allows 60 seconds for shutdown. Docker logs rotate at 10 MB per file with three files retained; Home Assistant's own files and database still require storage monitoring.

The initial deployment has no privileged mode, Docker socket, Bluetooth D-Bus mount or USB access. Add narrowly scoped hardware access when a specific integration requires it. Container installations do not include Supervisor-managed apps. Use the default SQLite database without an additional database service.

## Server preflight

Keep actual host addresses, container inventory, firewall output and resource measurements outside this public repository. Inspect the target server before deployment rather than relying on historical observations.

Remaining checks before startup:

- Run `scripts/preflight.sh` interactively on the server; it only reads system metadata and firewall rules. Sudo authentication may be required.
- Verify target directories are new, have suitable ownership and resolve to the intended locations. If existing Home Assistant data is found, stop and assess it before overwriting anything.
- Review UFW and nftables rules for access to host port 8123. Verify router forwarding and Tailscale access policy separately. Do not change network settings without separate approval.
- Verify that smart-home devices are reachable from the server's LAN. Host networking does not bypass VLAN isolation or router multicast restrictions.
- Verify a backup destination and its capacity. `/mnt/external` must be checked as an actual mounted filesystem before use.

## Installation

Run these commands on Ubuntu only after the remaining checks pass. They are not Windows paths. If the deployment directory already exists, inspect it instead of cloning over it.

```bash
git clone https://github.com/wirn/home-assistant.git /srv/docker/homeassistant
cd /srv/docker/homeassistant
cp -n .env.example .env
sudo install -d -m 0700 -o root -g root /srv/appdata/homeassistant
docker compose config --quiet
docker compose pull homeassistant
docker compose up -d homeassistant
```

Do not run the directory creation command against existing data until its permissions and backup requirements have been reviewed. The container initially runs as its image's default user; no LinuxServer-style PUID/PGID settings are used. The config bind mount disables automatic directory creation so a missing path produces an error.

## Verification and onboarding

```bash
cd /srv/docker/homeassistant
docker compose ps
docker compose logs --tail=100 homeassistant
curl --fail --silent --output /dev/null http://127.0.0.1:8123/
docker compose exec -T homeassistant python -m homeassistant --script check_config --config /config
```

Allow time for first startup and retry the HTTP check if needed. A running container alone does not establish application readiness. Compare existing container states with the preflight output.

Open `http://SERVER-LAN-IP:8123` on the home network and complete onboarding with a private password. Create individual household accounts. Configure Home Assistant's internal URL with its reachable LAN address, particularly for Cast media playback. The server currently uses DHCP; verify address stability without changing router settings automatically.

After onboarding, restart only Home Assistant and confirm the owner account and settings persist:

```bash
docker compose restart homeassistant
```

Repeat the readiness checks. Test desktop and mobile dashboards and the official Android/iOS Companion App. Configure the local URL and a reachable Tailscale URL for remote use. Tailscale devices must be connected and permitted by the existing tailnet policy. A desktop-only Tailscale test does not establish mobile access.

## Network and access

- TCP 8123 serves the Home Assistant UI/API on the host. Host mode has no Compose `ports` mapping and may listen on multiple host interfaces; verify firewall policy before startup.
- mDNS uses UDP 5353 and SSDP uses UDP 1900 for supported integrations. No existing listeners on those ports were shown by the initial inspection.
- Pi-hole's DNS port 53 and web port 80 are separate. Leave DNS settings unchanged.
- Remote access initially uses the existing Tailscale connection to `http://SERVER-TAILSCALE-IP:8123`. Traffic across Tailscale is encrypted; local HTTP depends on the trusted LAN. A future HTTPS reverse proxy requires a separate reviewed change.
- Do not configure public port forwarding, Tailscale Funnel, a new DNS record or a firewall exception as part of this deployment.

## Integrations

1. IKEA DIRIGERA: evaluate HomeKit Device first. Check existing pairing; HomeKit devices support one controller at a time. Do not remove an existing Apple Home pairing without approval.
2. Google Nest Audio: use Google Cast. Discovery requires appropriate LAN multicast access. Cast media URLs should use the reachable server LAN IP because Cast devices may not resolve Pi-hole-only names.
3. WiiM Amp Pro and Mini: use the official WiiM integration and verify local discovery/control.
4. Netatmo: use the official integration with the user's account. Cloud connectivity is required. Some device features and instant events require externally reachable webhooks; Tailscale-only access does not provide those.
5. Matter/Thread: defer to a separate change. Matter needs a separately managed server with Container; the officially supported Matter installation is Home Assistant OS. Verify IPv6, multicast, commissioning and border-router requirements first.
6. Future Zigbee/Thread coordinator: review the selected hardware and integration before adding device mappings or services.

Keep credentials out of documentation and terminal output. Accessible household dashboards and useful automations are configured after device pairing, with user input.

## Operations

Run service commands from `/srv/docker/homeassistant`:

```bash
docker compose ps
docker compose logs --tail=100 homeassistant
docker compose stop homeassistant
docker compose start homeassistant
```

To restart after configuration changes, validate configuration first, then restart only this service. Do not use Docker system prune or manage unrelated Compose stacks.

Monitor free disk space, database size and log growth. Home Assistant's default history retention is ten days, but long-term statistics can still grow. Keep enough free space for database maintenance and upgrades; review entity recording if storage becomes constrained.

## Backup

Use a verified backup filesystem and a private backup directory. Archives contain credentials and household data. Set restrictive permissions and keep an encrypted off-server copy. Do not place archives in this public Git repository.

For a consistent filesystem backup, stop only Home Assistant briefly. Substitute an existing absolute backup directory before running:

```bash
cd /srv/docker/homeassistant
backup_dir=/ABSOLUTE/VERIFIED/BACKUP/DIRECTORY
test -d "$backup_dir" && test -w "$backup_dir" || exit 1
backup_file="$backup_dir/homeassistant-$(date +%Y%m%d-%H%M%S).tar.gz"
umask 077
docker compose stop homeassistant
sudo sh -c 'umask 077; tar -czf "$1" -C /srv/appdata homeassistant' sh "$backup_file"
backup_result=$?
docker compose start homeassistant
if [ "$backup_result" -ne 0 ]; then exit "$backup_result"; fi
sudo tar -tzf "$backup_file" >/dev/null
```

These backup commands assume an interactive shell without `set -e`, so the service is restarted even if tar fails. If interrupted while stopped, start Home Assistant manually. Archive verification checks readability; periodically test restoration separately.

Record the deployed Git commit and `.env` image reference alongside each backup. Keep a secure copy of deployment settings if they later include private values. Backup retention and scheduling are not yet configured.

## Update and rollback

1. Review release notes and available disk space.
2. Make and verify a complete pre-update backup; record the current Git commit and image reference.
3. Change only `HA_IMAGE` in the server `.env` to an explicitly selected release.
4. Run `docker compose config --quiet`, `docker compose pull homeassistant`, and `docker compose up -d homeassistant`.
5. Verify logs, HTTP readiness, integrations and existing services.

Do not downgrade against a database already migrated by a newer release. To roll back, stop Home Assistant, preserve the failed version's config directory by moving it to a verified sibling location, restore the matching pre-update archive under `/srv/appdata`, restore its previous image setting, and start the service. Review exact paths and available capacity before any move or extraction. Never overwrite the only copy of persistent data.

## References

- [Home Assistant Container installation](https://www.home-assistant.io/installation/linux/)
- [Pinned release 2026.10.1](https://github.com/home-assistant/core/releases/tag/2026.10.1)
- [Recorder and storage requirements](https://www.home-assistant.io/integrations/recorder/)
- [HomeKit Device](https://www.home-assistant.io/integrations/homekit_controller/)
- [Google Cast](https://www.home-assistant.io/integrations/cast/)
- [WiiM](https://www.home-assistant.io/integrations/wiim/)
- [Netatmo](https://www.home-assistant.io/integrations/netatmo/)
- [Matter](https://www.home-assistant.io/integrations/matter/)

Local project instructions are maintained in `AGENTS.md`; this file is not included in the initial public commit because it contains environment-specific information.
