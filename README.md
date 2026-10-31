# proxmox-runaway

A [Proxmox VE community-scripts](https://github.com/community-scripts/ProxmoxVE) style addon that installs [Runaway](https://www.runaway.sh/), a self-hosted orchestrator for ephemeral GitHub Actions runners.

## Files

| File | Purpose |
| --- | --- |
| `tools/addon/runaway.sh` | Install / update / uninstall addon, modelled on the upstream `tools/addon/arcane.sh` |
| `json/runaway.json` | Website metadata in the community-scripts JSON format |

## Why an addon and not a `ct/` script

Community-scripts `ct/` and `install/` scripts must be bare-metal; Docker is only allowed in `tools/addon/*.sh` scripts that manage a Docker Compose stack. Runaway's official quickstart is Docker Compose, and its agent launches runners as Docker containers, so it ships as an addon.

## Usage

1. Create a Debian LXC with nesting enabled (for example with the community [Docker LXC](https://community-scripts.github.io/ProxmoxVE/scripts?id=docker)).
2. Inside that container, run:

   ```bash
   var_runaway_repo="<Runaway git URL from https://www.runaway.sh/docs>" \
     bash -c "$(curl -fsSL https://raw.githubusercontent.com/jt-pragmatic/proxmox-runaway/main/tools/addon/runaway.sh)"
   ```

   Leave `var_runaway_repo` unset to be prompted for it.
3. Open `http://<container-ip>:3000`, create the admin account, add a GitHub org with a classic PAT, and create a scale set.

The addon clones the repository to `/opt/runaway`, writes `/opt/runaway/.env` with freshly generated `RUNAWAY_MASTER_KEY`, `BETTER_AUTH_SECRET` and `RUNAWAY_LOCAL_AGENT_TOKEN`, and starts `docker-compose.example.yml`. Back up `RUNAWAY_MASTER_KEY`.

Update later with `update_runaway`, or re-run the addon to update or uninstall.
