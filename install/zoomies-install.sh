#!/usr/bin/env bash

# Copyright (C) 2026 Pragmatic Foundrie
# SPDX-License-Identifier: AGPL-3.0-only
# Derived in part from community-scripts ProxmoxVE (MIT), see NOTICE
# Source: https://github.com/eyupio/zoomies

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_docker

fetch_and_deploy_gh_release "zoomies" "eyupio/zoomies" "singlefile" "latest" "/usr/local/bin" "zoomies_linux_$(arch_resolve)"

if [[ -z "${var_zoomies_admin_pass:-}" ]]; then
  var_zoomies_admin_pass=$(random_password 20)
fi

msg_info "Configuring Zoomies"
# The answer file holds the admin password, so it lives only for the init run.
# Single quotes keep every password character literal in YAML; ' is written as ''.
admin_pass_yaml=${var_zoomies_admin_pass//\'/\'\'}
cat <<EOF >/root/zoomies-answers.yaml
mode: single
deployment: native
backend: docker
bind: 0.0.0.0:8080
tls:
  mode: "off"
external_url: ${var_zoomies_url:-http://${LOCAL_IP}:8080}
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
# catch_errors would exit before a plain rm runs, so clean up the answer file on failure too.
$STD zoomies init --answers /root/zoomies-answers.yaml --yes --no-tune --no-animation || {
  rm -f /root/zoomies-answers.yaml
  msg_error "zoomies init failed"
  exit 1
}
rm -f /root/zoomies-answers.yaml
msg_ok "Configured Zoomies"

motd_ssh
customize
cleanup_lxc
