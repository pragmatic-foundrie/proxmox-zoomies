#!/usr/bin/env bash

# Copyright (C) 2026 Pragmatic Foundrie
# SPDX-License-Identifier: AGPL-3.0-only
# Derived in part from community-scripts ProxmoxVE (MIT), see NOTICE
# Source: https://github.com/eyupio/zoomies

# ==============================================================================
# Zoomies VM - Debian 13 VM running Docker and the Zoomies controller
# ==============================================================================
# Runs on the Proxmox host. A full VM rather than an LXC so Docker gets its own
# kernel: runner containers get normal bridge networking and NAT for outbound
# traffic, and nothing needs nesting, keyctl or a relaxed seccomp filter.

export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/pragmatic-foundrie/proxmox-zoomies/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

# ==============================================================================
# SCRIPT VARIABLES
# ==============================================================================
APP="Zoomies"
APP_TYPE="vm"
NSAPP="zoomies-vm"
var_os="debian"
var_version="13"
var_arm64="yes"
ARCH=$(dpkg --print-architecture)

OS_CODENAME="trixie"
OS_DISPLAY="Debian 13 (Trixie)"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
METHOD=""
DISK_SIZE="20G"
USE_CLOUD_INIT="no"
THIN="discard=on,ssd=1,"

# Zoomies settings, passed into the guest's first-boot installer
var_zoomies_url="${var_zoomies_url:-}"
var_zoomies_admin_pass="${var_zoomies_admin_pass:-$(openssl rand -base64 30 | tr -dc 'A-Za-z0-9' | head -c 20)}"
# First boot installs packages from the internet; give slow links some room.
ZOOMIES_INSTALL_TIMEOUT="${ZOOMIES_INSTALL_TIMEOUT:-1200}"

if ((${#var_zoomies_admin_pass} < 12)); then
  msg_error "var_zoomies_admin_pass must be at least 12 characters"
  exit 1
fi

# ==============================================================================
# ERROR HANDLING & CLEANUP
# ==============================================================================
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

# ==============================================================================
# SETTINGS FUNCTIONS
# ==============================================================================
function get_image_url() {
  if [ "$USE_CLOUD_INIT" = "yes" ]; then
    echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${var_version}-generic-${ARCH}.qcow2"
  else
    echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${var_version}-nocloud-${ARCH}.qcow2"
  fi
}

function default_settings() {
  vm_apply_machine_type "q35"
  vm_prompt_cloud_init "root"

  VMID=$(get_valid_nextid)
  if [ "$ARCH" = "arm64" ]; then
    CPU_TYPE=""
  else
    CPU_TYPE=" -cpu host"
  fi
  DISK_CACHE=""
  DISK_SIZE="20G"
  HN="zoomies"
  CORE_COUNT="2"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  vm_prompt_cloud_init "root"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "20G"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "zoomies"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "4096"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_verbose "no"
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a Zoomies VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Zoomies VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

# ==============================================================================
# GUEST FILES
# ==============================================================================
# First-boot installer: Docker from Docker's apt repository, the Zoomies
# release binary, then `zoomies init`. Runs once as a systemd unit; a failed
# run is retried on the next boot.
function write_guest_installer() {
  cat <<'GUEST' >"$1"
#!/usr/bin/env bash
set -euo pipefail
exec > >(tee -a /var/log/zoomies-install.log) 2>&1
echo "[$(date -Is)] Zoomies install starting"

APT=(apt-get -o DPkg::Lock::Timeout=600 -y)
export DEBIAN_FRONTEND=noninteractive

for _ in $(seq 1 60); do
  curl -fsS -o /dev/null --max-time 5 https://github.com && break
  sleep 5
done

"${APT[@]}" update
"${APT[@]}" install ca-certificates curl jq qemu-guest-agent
systemctl enable --now qemu-guest-agent || true

# Docker CE from Docker's own repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
  >/etc/apt/sources.list.d/docker.list
"${APT[@]}" update
"${APT[@]}" install docker-ce docker-ce-cli containerd.io docker-buildx-plugin
mkdir -p /etc/docker
[[ -f /etc/docker/daemon.json ]] || cat <<'EOF' >/etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl enable docker
systemctl restart docker

# Zoomies binary
/usr/local/bin/update --install-only

# Answer file for zoomies init. It holds the admin password, so it lives only
# for the init run. Single quotes keep every password character literal in
# YAML; ' is written as ''.
admin_pass=$(cat /root/.zoomies-admin-pass)
admin_pass_yaml=${admin_pass//\'/\'\'}
external_url=$(cat /root/.zoomies-external-url 2>/dev/null || true)
if [[ -z "$external_url" ]]; then
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')
  external_url="http://${ip:-$(hostname -I | awk '{print $1}')}:8080"
fi
umask 077
trap 'rm -f /root/zoomies-answers.yaml' EXIT
cat <<EOF >/root/zoomies-answers.yaml
mode: single
deployment: native
backend: docker
bind: 0.0.0.0:8080
tls:
  mode: "off"
external_url: ${external_url}
github:
  skip: true
admin:
  username: admin
  password: '${admin_pass_yaml}'
service:
  manager: systemd
  enable: true
  start: true
EOF
zoomies init --answers /root/zoomies-answers.yaml --yes --no-tune --no-animation
rm -f /root/zoomies-answers.yaml /root/.zoomies-admin-pass /root/.zoomies-external-url

echo "[$(date -Is)] Zoomies install finished: ${external_url}"
GUEST
}

# `update` inside the VM: deploy the newest release and run zoomies upgrade.
function write_guest_updater() {
  cat <<'GUEST' >"$1"
#!/usr/bin/env bash
# Updates Zoomies to the latest GitHub release.
#   update                 download a newer release and run zoomies upgrade
#   update --install-only  download the release without upgrading (first boot)
set -euo pipefail

REPO="eyupio/zoomies"
VERSION_FILE="/root/.zoomies"

case "$(dpkg --print-architecture)" in
amd64) arch=amd64 ;;
arm64) arch=arm64 ;;
*) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac

latest=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name')
if [[ -z "$latest" || "$latest" == "null" ]]; then
  echo "Could not determine the latest Zoomies release" >&2
  exit 1
fi
current=$(cat "$VERSION_FILE" 2>/dev/null || true)

if [[ "${1:-}" != "--install-only" && "$current" == "$latest" ]]; then
  echo "Zoomies is already at ${latest}"
  exit 0
fi

echo "Downloading Zoomies ${latest}"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL -o "$tmp" "https://github.com/${REPO}/releases/download/${latest}/zoomies_linux_${arch}"
install -m 0755 "$tmp" /usr/local/bin/zoomies
echo "$latest" >"$VERSION_FILE"

if [[ "${1:-}" != "--install-only" ]]; then
  echo "Upgrading Zoomies"
  zoomies upgrade --no-download --non-interactive --yes --no-animation
fi
echo "Zoomies ${latest} installed"
GUEST
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
header_info

vm_preflight
vm_require_tools jq

vm_start_script "Use Default Settings?" 10 58
post_to_api_vm

vm_select_storage "$HN"

vm_ensure_virt_customize || {
  msg_error "virt-customize is required to stage the Zoomies installer into the image"
  exit 1
}

# ==============================================================================
# IMAGE DOWNLOAD
# ==============================================================================
msg_info "Retrieving the URL for the ${OS_DISPLAY} Qcow2 Disk Image"
URL=$(get_image_url)
CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="$CACHE_DIR/$(basename "$URL")"
mkdir -p "$CACHE_DIR"
msg_ok "${CL}${BL}${URL}${CL}"

vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes $((100 * 1024 * 1024)) || exit 115

# ==============================================================================
# IMAGE CUSTOMIZATION
# ==============================================================================
TEMP_DIR=$(mktemp -d)
WORK_FILE="$TEMP_DIR/$(basename "$CACHE_FILE")"
cp "$CACHE_FILE" "$WORK_FILE"

# Without cloud-init nothing grows the guest partition, so expand it offline.
if [ "$USE_CLOUD_INIT" != "yes" ]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$WORK_FILE" "$DISK_SIZE" || true
fi

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1
vm_prepare_cloud_image "$WORK_FILE" "$HN" || true

msg_info "Staging the Zoomies installer"
write_guest_installer "$TEMP_DIR/zoomies-firstboot"
write_guest_updater "$TEMP_DIR/update"
(
  umask 077
  printf '%s' "$var_zoomies_admin_pass" >"$TEMP_DIR/admin-pass"
  printf '%s' "$var_zoomies_url" >"$TEMP_DIR/external-url"
)
vm_customize "Zoomies files" "$WORK_FILE" \
  --upload "$TEMP_DIR/update:/usr/local/bin/update" \
  --chmod "0755:/usr/local/bin/update" \
  --upload "$TEMP_DIR/admin-pass:/root/.zoomies-admin-pass" \
  --chmod "0600:/root/.zoomies-admin-pass" \
  --upload "$TEMP_DIR/external-url:/root/.zoomies-external-url" \
  --chmod "0600:/root/.zoomies-external-url" || exit 1
vm_firstboot_unit "$WORK_FILE" "zoomies-firstboot" "$TEMP_DIR/zoomies-firstboot" \
  --description "Install Docker and Zoomies on first boot" || exit 1
rm -f "$TEMP_DIR/admin-pass" "$TEMP_DIR/external-url"
msg_ok "Staged the Zoomies installer"

# ==============================================================================
# VM CREATION
# ==============================================================================
vm_claim_vmid

msg_info "Creating Zoomies VM shell"
qm create "$VMID" -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores "$CORE_COUNT" -memory "$RAM_SIZE" \
  -name "$HN" -tags "community-script;ci;github" -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
msg_ok "Created VM shell"
vm_mark_created

vm_import_disk "$VMID" "$WORK_FILE" "$STORAGE"
rm -f "$WORK_FILE"

msg_info "Attaching EFI and root disk"
qm set "$VMID" \
  --efidisk0 "${STORAGE}:0,efitype=4m" \
  --scsi0 "${VM_IMPORTED_DISK},${DISK_CACHE}${THIN%,}" \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
msg_ok "Attached EFI and root disk"

vm_resize_disk scsi0 "$DISK_SIZE"
set_description

if [ "$USE_CLOUD_INIT" = "yes" ]; then
  msg_info "Configuring Cloud-Init"
  if vm_provision "$VMID"; then
    msg_ok "Cloud-Init configured"
  else
    msg_warn "VM created, but not provisioned"
  fi
fi

vm_start_vm "Zoomies VM"

# ==============================================================================
# WAIT FOR FIRST BOOT
# ==============================================================================
INSTALL_STATE=""
if [ "$START_VM" = "yes" ]; then
  msg_info "Installing Docker and Zoomies in the VM (this takes a few minutes)"
  deadline=$((SECONDS + ZOOMIES_INSTALL_TIMEOUT))
  while ((SECONDS < deadline)); do
    INSTALL_STATE="$(vm_guest_exec "$VMID" 15 systemctl is-active zoomies-firstboot.service 2>/dev/null | tr -d '[:space:]')" || true
    [[ "$INSTALL_STATE" == "active" || "$INSTALL_STATE" == "failed" ]] && break
    sleep 10
  done
  case "$INSTALL_STATE" in
  active) msg_ok "Installed Docker and Zoomies" ;;
  failed)
    msg_error "The Zoomies install inside the VM failed"
    vm_guest_exec "$VMID" 15 tail -n 20 /var/log/zoomies-install.log 2>/dev/null || true
    ;;
  *) msg_warn "Zoomies is still installing; follow it with: tail -f /var/log/zoomies-install.log" ;;
  esac
  vm_wait_for_ip || true
fi

# ==============================================================================
# FINAL OUTPUT
# ==============================================================================
ZOOMIES_URL="${var_zoomies_url:-http://${VM_IP:-<vm-ip>}:8080}"
vm_print_summary \
  "OS=${OS_DISPLAY}" \
  "URL=${ZOOMIES_URL}" \
  "Username=admin" \
  "Password=${var_zoomies_admin_pass}"

if [ "$USE_CLOUD_INIT" = "yes" ]; then
  display_cloud_init_info "$VMID" "$HN" 2>/dev/null || true
fi

vm_next_steps \
  "Open ${ZOOMIES_URL} and sign in as admin" \
  "Connect GitHub from the Installations page; Zoomies creates the GitHub App" \
  "Update later by running ${BL}update${CL} in the VM console" \
  "Install log inside the VM: /var/log/zoomies-install.log"

if [[ "$INSTALL_STATE" == "failed" ]]; then
  post_update_to_api "failed" "1"
  exit 1
fi
vm_finish
