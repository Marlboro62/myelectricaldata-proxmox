#!/usr/bin/env bash

# Copyright (c) 2026 Marlboro62
# Engine: community-scripts ORG (https://github.com/community-scripts/core)
# License: MIT | https://github.com/Marlboro62/myelectricaldata-proxmox/raw/main/LICENSE
# Source: https://github.com/MyElectricalData/myelectricaldata_new

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y nginx patch
msg_ok "Installed Dependencies"

PG_VERSION="17" setup_postgresql
PG_DB_NAME="myelectricaldata_client" PG_DB_USER="myelectricaldata" setup_postgresql_db
PYTHON_VERSION="3.11" setup_uv
NODE_VERSION="22" setup_nodejs

fetch_and_deploy_gh_release "myelectricaldata" "MyElectricalData/myelectricaldata_new" "tarball"

msg_info "Configuring MyElectricalData Backend"
cat <<EOF >/opt/myelectricaldata/.env
MED_CLIENT_ID=${var_med_client_id}
MED_CLIENT_SECRET=${var_med_client_secret}
MED_API_URL=https://www.v2.myelectricaldata.fr/api
DATABASE_URL=postgresql+asyncpg://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
VICTORIAMETRICS_URL=
SECRET_KEY=$(random_password 43)
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=43200
ALLOWED_HOSTS=
TZ=Europe/Paris
DEBUG=false
API_HOST=127.0.0.1
API_PORT=8000
PYTHONUNBUFFERED=1
EOF
chmod 600 /opt/myelectricaldata/.env
cd /opt/myelectricaldata/apps/api
$STD uv sync --no-dev --no-install-project
# Upstream hardcodes the Docker paths /app/static and /app/pyproject.toml
ln -sfn /opt/myelectricaldata/apps/api /app
msg_ok "Configured MyElectricalData Backend"

msg_info "Applying Local Patches"
cat <<'EOF' >/usr/local/bin/myelectricaldata-patches
#!/usr/bin/env bash
# Applies the local UI patches (e.g. "Passerelle" menu link) to the upstream sources
REPO=https://raw.githubusercontent.com/Marlboro62/myelectricaldata-proxmox/main/patches
cd /opt/myelectricaldata || exit 0
for p in lien-passerelle.patch; do
  if curl -fsSL "$REPO/$p" -o "/tmp/$p"; then
    if patch -p1 -N --dry-run -s <"/tmp/$p" >/dev/null 2>&1; then
      patch -p1 -N -s <"/tmp/$p" && echo "Applied $p"
    else
      echo "Skipped $p (already applied or not compatible with this version)"
    fi
    rm -f "/tmp/$p"
  fi
done
EOF
chmod +x /usr/local/bin/myelectricaldata-patches
$STD /usr/local/bin/myelectricaldata-patches
msg_ok "Applied Local Patches"

msg_info "Building MyElectricalData Frontend"
cd /opt/myelectricaldata/apps/web
export VITE_API_BASE_URL=/api
$STD npm ci
$STD npm run build
msg_ok "Built MyElectricalData Frontend"

msg_info "Setting up Version Badge"
mkdir -p /usr/local/share/myelectricaldata
cat <<'EOF' >/usr/local/share/myelectricaldata/badge.js
(function(){var SRC="/lxc-version.json",LINK="https://github.com/Marlboro62/myelectricaldata-proxmox#-mise-%C3%A0-jour",HINT="Tapez update dans la console du conteneur Proxmox",st=null,busy=false;function view(d){var n=d.behind||(d.update?1:0),c=n>=2?"#ef4444":n?"#f59e0b":"#22c55e",t="v"+d.version+(n>=2?" · <b>"+n+" versions de retard</b>":n?" · <b>"+d.latest+" disponible</b>":"");return{n:n,c:c,h:'<span style="display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:6px;background:'+c+'"></span>'+t}}function paint(){if(!st||busy)return;busy=true;try{var v=view(st);document.querySelectorAll("[data-app-version]").forEach(function(e){e.style.display="none"});document.querySelectorAll('a[href$="/preferences"]').forEach(function(a){if(a.textContent.indexOf("Préférences")<0)return;var e=a.nextElementSibling;if(!e||!e.classList||!e.classList.contains("med-ver")){e=document.createElement("a");e.className="med-ver";e.target="_blank";e.rel="noopener";e.href=LINK;e.style.cssText="display:block;padding:8px 12px 0;font:12px/1.4 system-ui,sans-serif;text-decoration:none";a.insertAdjacentElement("afterend",e)}if(e.getAttribute("data-h")!==v.h){e.innerHTML=v.h;e.setAttribute("data-h",v.h)}e.style.color=v.n>=2?"#ef4444":v.n?"#f59e0b":"#9ca3af";e.title=v.n?HINT+" (dernière version : "+st.latest+")":"À jour"})}finally{busy=false}}function load(){fetch("/lxc-version.json",{cache:"no-store"}).then(function(r){return r.ok?r.json():null}).then(function(d){if(d&&d.version){st=d;paint()}}).catch(function(){})}function start(){load();setInterval(load,9e5);var q=false;new MutationObserver(function(){if(q)return;q=true;requestAnimationFrame(function(){q=false;paint()})}).observe(document.body,{childList:true,subtree:true})}if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start);else start()})();
EOF
cat /usr/local/share/myelectricaldata/badge.js >>/opt/myelectricaldata/apps/web/dist/env.js
cat <<'EOF' >/usr/local/bin/myelectricaldata-version
#!/usr/bin/env bash
# Writes installed/latest MyElectricalData versions for the web UI badge
OUT=/opt/myelectricaldata/apps/web/dist/lxc-version.json
CUR=$(cat /root/.myelectricaldata 2>/dev/null)
CUR=${CUR#v}
[[ -z "$CUR" || ! -d ${OUT%/*} ]] && exit 0
TAGS=$(curl -fsSL --max-time 15 "https://api.github.com/repos/MyElectricalData/myelectricaldata_new/releases?per_page=50" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4 | grep -v '/' | sed 's/^v//')
LATEST=$(echo "$TAGS" | head -n1)
BEHIND=0
if [[ -n "$LATEST" && "$LATEST" != "$CUR" ]]; then
  POS=$(echo "$TAGS" | grep -n -x -F "$CUR" | cut -d: -f1)
  BEHIND=$((${POS:-2} - 1))
  ((BEHIND < 1)) && BEHIND=1
fi
printf '{"version":"%s","latest":"%s","behind":%d}\n' "$CUR" "${LATEST:-$CUR}" "$BEHIND" >"$OUT.tmp" && mv "$OUT.tmp" "$OUT"
EOF
chmod +x /usr/local/bin/myelectricaldata-version
cat <<'EOF' >/etc/systemd/system/myelectricaldata-version.service
[Unit]
Description=MyElectricalData version check for the web UI badge
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/myelectricaldata-version
EOF
cat <<'EOF' >/etc/systemd/system/myelectricaldata-version.timer
[Unit]
Description=MyElectricalData version check every 15 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
EOF
systemctl enable -q --now myelectricaldata-version.timer
/usr/local/bin/myelectricaldata-version || true
msg_ok "Set up Version Badge"

msg_info "Configuring Nginx"
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
nginx_enable_site "myelectricaldata"
msg_ok "Configured Nginx"

msg_info "Creating MyElectricalData Service"
cat <<EOF >/etc/systemd/system/myelectricaldata.service
[Unit]
Description=MyElectricalData Backend
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/myelectricaldata/apps/api
EnvironmentFile=/opt/myelectricaldata/.env
ExecStartPre=/opt/myelectricaldata/apps/api/.venv/bin/alembic upgrade head
ExecStart=/opt/myelectricaldata/apps/api/.venv/bin/uvicorn src.main:app --host 127.0.0.1 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now myelectricaldata
msg_ok "Created MyElectricalData Service"

msg_info "Adding Version Info to Login Banner"
cat <<'EOF' >/etc/profile.d/99-myelectricaldata.sh
if [[ -f /root/.myelectricaldata ]]; then
  _med_cur=$(cat /root/.myelectricaldata)
  _med_new=$(curl -fsSL --max-time 3 https://api.github.com/repos/MyElectricalData/myelectricaldata_new/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | cut -d'"' -f4)
  echo -e "    📦 MyElectricalData : ${_med_cur#v}"
  if [[ -n "$_med_new" && "${_med_new#v}" != "${_med_cur#v}" ]]; then
    echo -e "    ⬆️  Mise à jour disponible : ${_med_new#v} (tapez : update)"
  else
    echo -e "    ✅ MyElectricalData est à jour"
  fi
  echo
  unset _med_cur _med_new
fi
EOF
msg_ok "Added Version Info to Login Banner"

motd_ssh
customize
cleanup_lxc
