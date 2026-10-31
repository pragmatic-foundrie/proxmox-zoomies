#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jt-pragmatic
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
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
  password: "${var_zoomies_admin_pass}"
service:
  manager: systemd
  enable: true
  start: true
EOF
$STD zoomies init --answers /root/zoomies-answers.yaml --yes --no-tune --no-animation
rm -f /root/zoomies-answers.yaml
msg_ok "Configured Zoomies"

motd_ssh
customize
cleanup_lxc
