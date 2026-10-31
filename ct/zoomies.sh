#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (C) 2026 Pragmatic Foundrie
# SPDX-License-Identifier: AGPL-3.0-only
# Derived in part from community-scripts ProxmoxVE (MIT), see NOTICE
# Source: https://github.com/eyupio/zoomies

APP="Zoomies"
var_tags="${var_tags:-ci;github}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
# Runners are Docker containers started inside this LXC
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

export var_zoomies_url="${var_zoomies_url:-}"
export var_zoomies_admin_pass="${var_zoomies_admin_pass:-$(random_password 20)}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/zoomies/zoomies.yaml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "zoomies" "eyupio/zoomies"; then
    fetch_and_deploy_gh_release "zoomies" "eyupio/zoomies" "singlefile" "latest" "/usr/local/bin" "zoomies_linux_$(arch_resolve)"

    msg_info "Upgrading Zoomies"
    $STD zoomies upgrade --no-download --non-interactive --yes --no-animation
    msg_ok "Upgraded Zoomies"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}${var_zoomies_url:-http://${IP}:8080}${CL}"
echo -e "${INFO}${YW}Credentials:${CL}"
echo -e "${TAB}${BGN}Username: admin${CL}"
echo -e "${TAB}${BGN}Password: ${var_zoomies_admin_pass}${CL}"
echo -e "${INFO}${YW}Sign in and connect GitHub from the Installations page to create the GitHub App.${CL}"
