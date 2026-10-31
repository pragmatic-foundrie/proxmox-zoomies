# proxmox-zoomies

[Proxmox VE community-scripts](https://github.com/community-scripts/ProxmoxVE) style script that creates a VM running [Zoomies](https://zoomies.sh/), a self-hosted GitHub Actions runner fleet controller.

Zoomies runs each job in a Docker container. Earlier versions used an LXC, where Docker shares the Proxmox host kernel and runner containers had trouble reaching the internet. A VM gives Docker its own kernel, so containers get normal bridge networking and NAT for outbound traffic. It also removes the need for `nesting`, `keyctl` and the relaxed seccomp filter.

## Files

| File | Purpose |
| --- | --- |
| `vm/zoomies-vm.sh` | Runs on the Proxmox host: builds the VM image, creates the VM and waits for Zoomies to come up |
| `json/zoomies.json` | Website metadata in the community-scripts JSON format |

## What it installs

- Debian 13 cloud image, 2 vCPU / 4 GB RAM / 20 GB disk, q35 + UEFI (amd64) or `virt` (arm64), QEMU guest agent.
- On first boot, a `zoomies-firstboot` systemd unit installs:
  - Docker CE from Docker's apt repository, used as the runner backend so each job gets its own ephemeral container.
  - The `zoomies_linux_<arch>` release binary at `/usr/local/bin/zoomies`.
  - `zoomies init` in native mode with an embedded agent (`mode: single`), so the controller runs as the `zoomies` systemd service on port 8080.
- An `update` command in the VM (`/usr/local/bin/update`).

The host script uses `virt-customize` to stage the installer into the image. It installs `libguestfs-tools` on the Proxmox host if it is missing.

## Usage

On the Proxmox host shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/pragmatic-foundrie/proxmox-zoomies/main/vm/zoomies-vm.sh)"
```

Pick **Default** or **Advanced** settings (VM ID, disk, CPU, RAM, bridge, VLAN, Cloud-Init and so on). The script downloads the image, creates the VM, starts it and waits until Docker and Zoomies are installed. At the end it prints the URL and the `admin` password. Sign in, connect GitHub from the Installations page (Zoomies creates the GitHub App), and the first pool is created for you.

Optional settings:

| Variable | Default | Meaning |
| --- | --- | --- |
| `var_zoomies_url` | `http://<vm-ip>:8080` | External URL GitHub and browsers use |
| `var_zoomies_admin_pass` | generated | Admin password (12+ characters) |
| `ZOOMIES_INSTALL_TIMEOUT` | `1200` | Seconds to wait for the first-boot install before printing the summary anyway |
| `VM_UNATTENDED` | `0` | `1` skips the dialogs and uses the defaults; override them with `VM_VMID`, `VM_STORAGE`, `VM_CORES`, `VM_RAM`, `VM_DISK_SIZE`, `VM_BRIDGE`, `VM_VLAN`, `VM_HOSTNAME` and so on |

For example:

```bash
VM_UNATTENDED=1 VM_STORAGE=local-lvm var_zoomies_url=https://zoomies.example.com \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/pragmatic-foundrie/proxmox-zoomies/main/vm/zoomies-vm.sh)"
```

Without Cloud-Init the console logs in as `root` automatically. With Cloud-Init you set the user, password and SSH keys in the dialogs.

Without a public `https://` external URL, GitHub can't deliver webhooks and Zoomies falls back to polling. Put a TLS reverse proxy in front for instant scaling.

The default external URL uses the address the VM got from DHCP. Give the VM a DHCP reservation (or a static IP via Cloud-Init) so the URL keeps working.

## Updating

Run `update` in the VM console. It downloads the newest release binary and runs `zoomies upgrade --no-download`, which backs up the database, updates the service units and restarts them.

## Moving from the LXC version

The LXC scripts (`ct/zoomies.sh`, `install/zoomies-install.sh`) have been removed, and `update` in an old container no longer has a script to fetch. To move:

1. Create the VM with this script.
2. Reconnect GitHub from the new instance's Installations page, and recreate your pools.
3. Remove the old GitHub App and destroy the LXC.

## Troubleshooting

- `Could not install libguestfs-tools`: the script prints apt's error. Usually the `pve-enterprise` (or Ceph enterprise) repository is enabled without a subscription. Disable it under **Node > Updates > Repositories**, add the `no-subscription` repository, then check that `apt-get update && apt-get install -y libguestfs-tools` works on the host.
- Install log inside the VM: `/var/log/zoomies-install.log`, or `journalctl -u zoomies-firstboot`.
- A failed first-boot install runs again on the next boot. You can also rerun it with `systemctl restart zoomies-firstboot`.
- Check that runner containers can reach the internet: `docker run --rm curlimages/curl -sI https://github.com`.

## Security notes

- Zoomies serves plain HTTP on port 8080 by default, so the admin password crosses your network unencrypted. Put a TLS reverse proxy in front before exposing it beyond your LAN.
- The admin password is staged in the image at `/root/.zoomies-admin-pass` (mode 0600) and deleted once `zoomies init` succeeds.
- Without Cloud-Init the VM console logs in as `root` with no password. Anyone with console access to the VM in Proxmox has root. Set a root password (`passwd`) if that matters to you.
- The Zoomies binary comes from the latest GitHub release without a pinned checksum. Only update from releases you trust.

## License

Licensed under the GNU Affero General Public License v3.0 only. See [LICENSE](LICENSE). Portions are derived from community-scripts ProxmoxVE (MIT). See [NOTICE](NOTICE).
