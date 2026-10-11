#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/Marlboro62/myelectricaldata-proxmox/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2026 Marlboro62
# Engine: community-scripts ORG (https://github.com/community-scripts/core)
# License: MIT | https://github.com/Marlboro62/myelectricaldata-proxmox/raw/main/LICENSE
# Source: https://github.com/MyElectricalData/myelectricaldata_new

APP="MyElectricalData"
var_tags="${var_tags:-energy;linky;home-automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/myelectricaldata ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "myelectricaldata" "MyElectricalData/myelectricaldata_new"; then
    msg_info "Stopping MyElectricalData"
    systemctl stop myelectricaldata
    msg_ok "Stopped MyElectricalData"

    create_backup /opt/myelectricaldata/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "myelectricaldata" "MyElectricalData/myelectricaldata_new" "tarball"

    restore_backup

    msg_info "Updating MyElectricalData Backend"
    cd /opt/myelectricaldata/apps/api
    $STD uv sync --no-dev --no-install-project
    msg_ok "Updated MyElectricalData Backend"

    msg_info "Applying Local Patches"
    command -v patch >/dev/null || $STD apt install -y patch
    $STD /usr/local/bin/myelectricaldata-patches
    msg_ok "Applied Local Patches"

    msg_info "Building MyElectricalData Frontend"
    cd /opt/myelectricaldata/apps/web
    export VITE_API_BASE_URL=/api
    $STD npm ci
    $STD npm run build
    cat /usr/local/share/myelectricaldata/badge.js >>/opt/myelectricaldata/apps/web/dist/env.js
    msg_ok "Built MyElectricalData Frontend"

    if ! grep -q "no-cache" /etc/nginx/sites-available/myelectricaldata; then
      msg_info "Updating Nginx Configuration"
      cat <<'EOF' >/etc/nginx/sites-available/myelectricaldata
server {
    listen 8100;
    server_name _;

    root /opt/myelectricaldata/apps/web/dist;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }

    # Always revalidate the entry files so a new version is picked up after an update
    location = /index.html {
        add_header Cache-Control "no-cache";
    }
    location = /env.js {
        add_header Cache-Control "no-cache";
    }
    location = /lxc-version.json {
        add_header Cache-Control "no-cache";
    }

    # Build assets have a content hash in their name: cache them for a long time
    location /assets/ {
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
      msg_ok "Updated Nginx Configuration"
    fi

    msg_info "Starting MyElectricalData"
    systemctl start myelectricaldata
    systemctl reload nginx
    /usr/local/bin/myelectricaldata-version || true
    msg_ok "Started MyElectricalData"
    msg_ok "Updated successfully!"
  fi
  exit
}

if command -v pveversion >/dev/null 2>&1; then
  if [[ -z "${var_med_client_id:-}" ]]; then
    read -rp "MyElectricalData Client ID (cli_...): " var_med_client_id
  fi
  if [[ -z "${var_med_client_secret:-}" ]]; then
    read -rsp "MyElectricalData Client Secret: " var_med_client_secret
    echo
  fi
  export var_med_client_id var_med_client_secret
fi

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}API credentials are stored in /opt/myelectricaldata/.env (restart after editing: systemctl restart myelectricaldata)${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8100${CL}"
