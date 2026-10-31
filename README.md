# proxmox-zoomies

[Proxmox VE community-scripts](https://github.com/community-scripts/ProxmoxVE) style scripts that create an LXC running [Zoomies](https://zoomies.sh/), a self-hosted GitHub Actions runner fleet controller.

## Files

| File | Purpose |
| --- | --- |
| `ct/zoomies.sh` | Runs on the Proxmox host: creates the LXC and handles updates |
| `install/zoomies-install.sh` | Runs inside the LXC: installs Docker and Zoomies, then runs `zoomies init` |
| `json/zoomies.json` | Website metadata in the community-scripts JSON format |

## What it installs

- Debian 13, unprivileged, 2 vCPU / 4 GB RAM / 20 GB disk, nesting and keyctl on.
- The `zoomies_linux_<arch>` release binary at `/usr/local/bin/zoomies` (amd64 and arm64).
- Docker, used as the runner backend so each job gets its own ephemeral container.
- `zoomies init` in native mode with an embedded agent (`mode: single`), so the controller runs as the `zoomies` systemd service, listening on port 8080.

## Usage

On the Proxmox host shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/pragmatic-foundrie/proxmox-zoomies/main/ct/zoomies.sh)"
```

Optional settings:

| Variable | Default | Meaning |
| --- | --- | --- |
| `var_zoomies_url` | `http://<container-ip>:8080` | External URL GitHub and browsers use |
| `var_zoomies_admin_pass` | generated | Admin password (12+ characters) |
| `COMMUNITY_SCRIPTS_URL` | this repo's `main` branch | Where the engine fetches `install/zoomies-install.sh` from. Point it at a fork or branch to test changes |

To test a branch, set both the script URL and the scripts base:

```bash
COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/pragmatic-foundrie/proxmox-zoomies/<branch> \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/pragmatic-foundrie/proxmox-zoomies/<branch>/ct/zoomies.sh)"
```

At the end the script prints the URL and the `admin` password. Sign in, connect GitHub from the Installations page (Zoomies creates the GitHub App), and the first pool is created for you.

Without a public `https://` external URL, GitHub can't deliver webhooks and Zoomies falls back to polling. Put a TLS reverse proxy in front for instant scaling.

## Updating

Run the same command inside the container (or `update` from its console). It deploys the newest release binary and runs `zoomies upgrade --no-download`, which backs up the database, updates the service units and restarts them.

## Security notes

- Zoomies serves plain HTTP on port 8080 by default, so the admin password crosses your network unencrypted. Put a TLS reverse proxy in front before exposing it beyond your LAN.
- Runners are Docker containers, so the LXC needs `nesting` and `keyctl`. That widens what the container can do compared with a plain LXC.
- The Zoomies binary comes from the latest GitHub release without a pinned checksum. Only update from releases you trust.

## License

Licensed under the GNU Affero General Public License v3.0 only. See [LICENSE](LICENSE). Portions are derived from community-scripts ProxmoxVE (MIT). See [NOTICE](NOTICE).
