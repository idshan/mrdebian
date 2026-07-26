#!/usr/bin/env bash
set -Eeuo pipefail

# VLESS WebSocket TLS Manager — pemasangan dari VPS kosong.
# Sokongan: Ubuntu 22.04/24.04 dan Debian 11/12.

APP_DIR="/etc/vless-ws"
DB_FILE="${APP_DIR}/users.tsv"
ENV_FILE="${APP_DIR}/server.env"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
MANAGER="/usr/local/sbin/vless-manager"
NGINX_SITE="/etc/nginx/sites-available/vless-ws"
WEBROOT="/var/www/vless-ws"
XRAY_PORT=10000

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
reset='\033[0m'

die() {
  echo -e "${red}RALAT:${reset} $*" >&2
  exit 1
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "Jalankan sebagai root."
}

valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9_-]{1,32}$ ]]
}

load_env() {
  [[ -r "${ENV_FILE}" ]] || die "Server belum dipasang. Pilih Install."
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
}

install_xray() {
  if ! command -v xray >/dev/null 2>&1; then
    bash <(curl -fsSL \
      https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
  fi
}

rebuild_xray() {
  load_env
  local clients='[]'
  local name uuid expires

  touch "${DB_FILE}"
  while IFS=$'\t' read -r name uuid expires; do
    [[ -n "${name}" && -n "${uuid}" ]] || continue
    clients="$(
      jq -c \
        --arg id "${uuid}" \
        --arg email "${name}" \
        '. + [{"id":$id,"email":$email}]' <<<"${clients}"
    )"
  done < "${DB_FILE}"

  install -d -m 755 "$(dirname "${XRAY_CONFIG}")"
  jq -n \
    --argjson clients "${clients}" \
    --arg path "${WS_PATH}" \
    --argjson port "${XRAY_PORT}" \
    '{
      log: {loglevel: "warning"},
      inbounds: [{
        tag: "vless-ws",
        listen: "127.0.0.1",
        port: $port,
        protocol: "vless",
        settings: {
          clients: $clients,
          decryption: "none"
        },
        streamSettings: {
          network: "ws",
          security: "none",
          wsSettings: {path: $path}
        }
      }],
      outbounds: [
        {tag: "direct", protocol: "freedom"},
        {tag: "blocked", protocol: "blackhole"}
      ]
    }' > "${XRAY_CONFIG}.new"

  xray run -test -config "${XRAY_CONFIG}.new"
  mv "${XRAY_CONFIG}.new" "${XRAY_CONFIG}"
  systemctl restart xray
}

make_link() {
  local uuid="$1"
  local name="$2"
  local encoded_path="${WS_PATH//\//%2F}"
  printf '%s\n' \
    "vless://${uuid}@${CLIENT_ADDRESS}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${encoded_path}#${name}"
}

add_user() {
  load_env
  local name days uuid expiry expiry_epoch

  read -r -p "Nama pengguna: " name
  valid_name "${name}" || die "Gunakan huruf, nombor, _ atau - sahaja."
  grep -q "^${name}"$'\t' "${DB_FILE}" 2>/dev/null &&
    die "Pengguna ${name} sudah wujud."

  read -r -p "Tempoh akaun dalam hari: " days
  [[ "${days}" =~ ^[1-9][0-9]*$ ]] || die "Bilangan hari tidak sah."
  (( days <= 3650 )) || die "Tempoh maksimum ialah 3650 hari."

  uuid="$(xray uuid)"
  expiry_epoch="$(( $(date +%s) + days * 86400 ))"
  expiry="$(date -u -d "@${expiry_epoch}" +%Y-%m-%d)"
  printf '%s\t%s\t%s\n' "${name}" "${uuid}" "${expiry}" >> "${DB_FILE}"

  rebuild_xray
  echo -e "${green}Pengguna berjaya ditambah.${reset}"
  echo "Nama   : ${name}"
  echo "Tamat  : ${expiry}"
  echo "UUID   : ${uuid}"
  echo "Link   :"
  make_link "${uuid}" "${name}"
}

delete_user() {
  load_env
  local name temp

  read -r -p "Nama pengguna yang mahu dipadam: " name
  grep -q "^${name}"$'\t' "${DB_FILE}" 2>/dev/null ||
    die "Pengguna tidak ditemui."

  temp="$(mktemp)"
  awk -F '\t' -v target="${name}" '$1 != target' "${DB_FILE}" > "${temp}"
  install -m 600 "${temp}" "${DB_FILE}"
  rm -f "${temp}"

  rebuild_xray
  echo -e "${green}Pengguna ${name} telah dipadam.${reset}"
}

list_users() {
  load_env
  local today name uuid expiry status
  today="$(date -u +%Y-%m-%d)"

  printf '%-20s %-38s %-12s %s\n' "NAMA" "UUID" "TAMAT" "STATUS"
  printf '%-20s %-38s %-12s %s\n' "----" "----" "-----" "------"
  while IFS=$'\t' read -r name uuid expiry; do
    [[ -n "${name}" ]] || continue
    status="Aktif"
    [[ "${expiry}" < "${today}" ]] && status="Tamat"
    printf '%-20s %-38s %-12s %s\n' \
      "${name}" "${uuid}" "${expiry}" "${status}"
  done < "${DB_FILE}"
}

purge_expired() {
  load_env
  local today temp before after
  today="$(date -u +%Y-%m-%d)"
  temp="$(mktemp)"
  before="$(wc -l < "${DB_FILE}")"

  awk -F '\t' -v today="${today}" '$3 >= today' "${DB_FILE}" > "${temp}"
  install -m 600 "${temp}" "${DB_FILE}"
  rm -f "${temp}"
  after="$(wc -l < "${DB_FILE}")"

  if [[ "${before}" != "${after}" ]]; then
    rebuild_xray
  fi
}

show_user_link() {
  load_env
  local name row uuid expiry
  read -r -p "Nama pengguna: " name
  row="$(awk -F '\t' -v target="${name}" '$1 == target {print; exit}' "${DB_FILE}")"
  [[ -n "${row}" ]] || die "Pengguna tidak ditemui."
  IFS=$'\t' read -r name uuid expiry <<<"${row}"
  echo "Tamat: ${expiry}"
  make_link "${uuid}" "${name}"
}

install_server() {
  need_root
  local email

  [[ -r /etc/os-release ]] || die "Sistem operasi tidak dapat dikenal pasti."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "Hanya Ubuntu dan Debian disokong." ;;
  esac

  read -r -p "Masukkan domain untuk TLS: " DOMAIN
  [[ "${DOMAIN}" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] ||
    die "Format domain tidak sah."

  read -r -p "Email Let's Encrypt (boleh kosong): " email
  read -r -p "WS Path [/vless]: " WS_PATH
  WS_PATH="${WS_PATH:-/vless}"
  [[ "${WS_PATH}" == /* ]] || die "WS Path mesti bermula dengan /."

  read -r -p "Address klien/CDN [${DOMAIN}]: " CLIENT_ADDRESS
  CLIENT_ADDRESS="${CLIENT_ADDRESS:-${DOMAIN}}"

  echo "Pastikan DNS ${DOMAIN} sudah menunjuk ke IP VPS."
  read -r -p "Teruskan pemasangan? [y/N]: " confirm
  [[ "${confirm}" =~ ^[Yy]$ ]] || die "Pemasangan dibatalkan."

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl ca-certificates unzip nginx certbot jq ufw
  install_xray

  install -d -m 700 "${APP_DIR}"
  install -d -m 755 "${WEBROOT}"
  touch "${DB_FILE}"
  chmod 600 "${DB_FILE}"

  cat > "${ENV_FILE}" <<EOF
DOMAIN='${DOMAIN}'
CLIENT_ADDRESS='${CLIENT_ADDRESS}'
WS_PATH='${WS_PATH}'
XRAY_PORT='${XRAY_PORT}'
EOF
  chmod 600 "${ENV_FILE}"

  cat > "${WEBROOT}/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Welcome</title></head>
<body><h1>Welcome</h1></body>
</html>
EOF

  rm -f /etc/nginx/sites-enabled/default
  cat > "${NGINX_SITE}" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${DOMAIN};
    root ${WEBROOT};

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
  ln -sfn "${NGINX_SITE}" /etc/nginx/sites-enabled/vless-ws
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx

  local certbot_args=(
    certonly --webroot
    -w "${WEBROOT}"
    -d "${DOMAIN}"
    --non-interactive
    --agree-tos
  )
  if [[ -n "${email}" ]]; then
    certbot_args+=(--email "${email}")
  else
    certbot_args+=(--register-unsafely-without-email)
  fi
  certbot "${certbot_args[@]}"

  cat > "${NGINX_SITE}" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${WEBROOT};
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    root ${WEBROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location = ${WS_PATH} {
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_pass http://127.0.0.1:${XRAY_PORT};
    }
}
EOF

  cp -f "$0" "${MANAGER}"
  chmod 700 "${MANAGER}"
  ln -sfn "${MANAGER}" /usr/local/bin/menu

  cat > /etc/cron.d/vless-expiry <<EOF
15 0 * * * root ${MANAGER} purge >/dev/null 2>&1
EOF
  chmod 644 /etc/cron.d/vless-expiry

  rebuild_xray
  nginx -t
  systemctl enable xray nginx
  systemctl restart xray
  systemctl reload nginx

  ufw allow OpenSSH >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null

  echo -e "${green}Pemasangan TLS berjaya.${reset}"
  echo "Jalankan menu menggunakan: menu"
  echo "Atau gunakan: vless-manager"
  add_user
}

menu() {
  while true; do
    clear
    echo "======================================"
    echo " VLESS WebSocket TLS Manager"
    echo "======================================"
    echo " 1. Install server dari kosong"
    echo " 2. Add user"
    echo " 3. Delete user"
    echo " 4. List user"
    echo " 5. Papar link user"
    echo " 6. Padam akaun tamat tempoh"
    echo " 7. Restart Xray dan Nginx"
    echo " 0. Keluar"
    echo "======================================"
    read -r -p "Pilihan: " choice

    case "${choice}" in
      1) install_server ;;
      2) add_user ;;
      3) delete_user ;;
      4) list_users ;;
      5) show_user_link ;;
      6) purge_expired; echo "Pembersihan selesai." ;;
      7)
        systemctl restart xray nginx
        echo "Servis telah dimulakan semula."
        ;;
      0) exit 0 ;;
      *) echo "Pilihan tidak sah." ;;
    esac
    read -r -p "Tekan Enter untuk kembali ke menu..." _
  done
}

need_root
case "${1:-menu}" in
  install) install_server ;;
  add) add_user ;;
  delete) delete_user ;;
  list) list_users ;;
  link) show_user_link ;;
  purge) purge_expired ;;
  menu) menu ;;
  *) die "Arahan: $0 [install|add|delete|list|link|purge|menu]" ;;
esac
