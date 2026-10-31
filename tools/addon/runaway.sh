#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jt-pragmatic
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.runaway.sh/
if ! command -v curl &>/dev/null; then
  printf "\r\e[2K%b" '\033[93m Setup Source \033[m' >&2
  if [[ -f /etc/alpine-release ]]; then
    apk update >/dev/null 2>&1
    apk add --no-cache curl >/dev/null 2>&1
  else
    apt-get update >/dev/null 2>&1
    apt-get install -y curl >/dev/null 2>&1
  fi
fi
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/core.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/lib/tools.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/error_handler.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/api/api.func") 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "runaway" "addon"

set -Eeuo pipefail
trap 'error_handler' ERR

APP="Runaway"
APP_TYPE="addon"
INSTALL_PATH="/opt/runaway"
ENV_FILE="${INSTALL_PATH}/.env"
DEFAULT_PORT=3000

load_functions

function uninstall() {
  msg_info "Uninstalling ${APP}"
  cd "$INSTALL_PATH"
  $STD docker compose down --volumes --remove-orphans
  cd /
  rm -rf "$INSTALL_PATH"
  rm -f "/usr/local/bin/update_runaway"
  msg_ok "${APP} has been uninstalled"
}

function update() {
  cd "$INSTALL_PATH"

  msg_info "Pulling latest ${APP} source"
  $STD git pull --ff-only
  msg_ok "Pulled latest source"

  msg_info "Pulling latest ${APP} images"
  $STD docker compose pull --ignore-buildable
  msg_ok "Pulled latest images"

  msg_info "Restarting ${APP}"
  $STD docker compose up -d --build --remove-orphans
  msg_ok "Restarted ${APP}"

  msg_ok "Updated successfully"
  exit
}

function install() {
  ensure_docker

  msg_info "Installing Dependencies"
  $STD apt install -y git openssl
  msg_ok "Installed Dependencies"

  msg_info "Cloning ${APP}"
  $STD git clone --depth 1 "$var_runaway_repo" "$INSTALL_PATH"
  msg_ok "Cloned ${APP} to ${INSTALL_PATH}"

  # Upstream quickstart generates these with openssl rand -base64 32; the master
  # key is used for encryption, so keep the 32 random bytes instead of random_password.
  msg_info "Configuring ${APP}"
  cat <<EOF >"$ENV_FILE"
COMPOSE_FILE=docker-compose.example.yml
RUNAWAY_MASTER_KEY=$(openssl rand -base64 32)
BETTER_AUTH_SECRET=$(openssl rand -base64 32)
RUNAWAY_LOCAL_AGENT_TOKEN=$(openssl rand -base64 32)
EOF
  chmod 600 "$ENV_FILE"
  msg_ok "Configured ${APP}"

  msg_info "Starting ${APP}"
  cd "$INSTALL_PATH"
  $STD docker compose up -d --build
  msg_ok "Started ${APP}"

  msg_info "Creating update script"
  cat <<'UPDATEEOF' >/usr/local/bin/update_runaway
#!/usr/bin/env bash
# Runaway Update Script
type=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/jt-pragmatic/proxmox-runaway/main/tools/addon/runaway.sh)"
UPDATEEOF
  chmod +x /usr/local/bin/update_runaway
  msg_ok "Created update script (/usr/local/bin/update_runaway)"

  echo ""
  msg_ok "${APP} is reachable at: ${BL}http://${LOCAL_IP}:${DEFAULT_PORT}${CL}"
  echo ""
  echo -e "${TAB}${INFO} Create your admin account on first access, then add a GitHub org"
  echo -e "${TAB}  with a classic PAT and create a scale set."
  msg_warn "Secrets are stored in ${ENV_FILE}. Back up RUNAWAY_MASTER_KEY; without it stored credentials cannot be decrypted."
}

if [[ "${type:-}" == "update" ]]; then
  header_info
  if [[ -f "$ENV_FILE" ]]; then
    update
  else
    msg_error "${APP} is not installed. Nothing to update."
    exit 233
  fi
  exit 0
fi

header_info
confirm_not_pve_host
get_lxc_ip

if [[ -f "$ENV_FILE" ]]; then
  msg_warn "${APP} is already installed."
  echo ""

  echo -n "${TAB}Uninstall ${APP}? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall
    exit 0
  fi

  echo -n "${TAB}Update ${APP}? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    update
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

msg_warn "${APP} is not installed."
echo ""
echo -e "${TAB}${INFO} This will install:"
echo -e "${TAB}  - Docker (if missing)"
echo -e "${TAB}  - Runaway hub and local agent (via Docker Compose)"
echo -e "${TAB}${INFO} Run this inside a Debian LXC with nesting enabled (e.g. the community Docker LXC)."
echo ""

if [[ -z "${var_runaway_repo:-}" ]]; then
  read -r -p "${TAB}Runaway Git repository URL (see https://www.runaway.sh/docs): " var_runaway_repo || true
fi
if [[ -z "${var_runaway_repo:-}" ]]; then
  msg_error "A Runaway repository URL is required. Set var_runaway_repo or enter it at the prompt."
  exit 1
fi

echo -n "${TAB}Install ${APP}? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi
