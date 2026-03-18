#!/usr/bin/env bash
# =============================================================================
# Управление gost прокси: set/on/off/status
# Использование:
#   gost-toggle.sh set <proxy_ip> <proxy_port> <login> <password>
#   gost-toggle.sh <on|off|status>
# =============================================================================
set -euo pipefail

GOST_CONFIG="/etc/gost/config.yaml"
GOST_UPSTREAM_FILE="/etc/gost/upstream.conf"

usage() {
  cat >&2 <<EOF
Использование:
  $0 set <proxy_ip> <proxy_port> <login> <password>
  $0 <off|on|status>

Команды:
  set     Задать параметры upstream SOCKS5 прокси и включить
  on      Включить upstream прокси (параметры из последнего set)
  off     Отключить upstream (direct-режим)
  status  Показать текущий режим и статус сервиса
EOF
}

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo "Запустите от имени root" >&2
    exit 1
  fi
}

validate_ip() {
  local ip="$1"
  if [[ ! "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Неверный IP-адрес прокси: ${ip}" >&2
    exit 1
  fi
}

validate_port() {
  local title="$1" value="$2"
  if [[ ! "${value}" =~ ^[0-9]+$ ]] || [ "${value}" -lt 1 ] || [ "${value}" -gt 65535 ]; then
    echo "Неверный ${title}: ${value}" >&2
    exit 1
  fi
}

# --- Сохранить параметры upstream для on/off ---
save_upstream() {
  local ip="$1" port="$2" login="$3" password="$4"
  mkdir -p /etc/gost
  cat > "${GOST_UPSTREAM_FILE}" <<EOF
UPSTREAM_IP=${ip}
UPSTREAM_PORT=${port}
UPSTREAM_LOGIN=${login}
UPSTREAM_PASSWORD=${password}
EOF
  chmod 600 "${GOST_UPSTREAM_FILE}"
}

load_upstream() {
  if [ ! -f "${GOST_UPSTREAM_FILE}" ]; then
    echo "Параметры upstream не заданы. Сначала выполните: $0 set <ip> <port> <login> <password>" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${GOST_UPSTREAM_FILE}"
}

# --- Генерация конфигов ---
write_direct_config() {
  cat > "${GOST_CONFIG}" <<'EOF'
services:
  - name: local-socks5
    addr: ":1080"
    handler:
      type: socks5
    listener:
      type: tcp
EOF
}

write_proxy_config() {
  local ip="$1" port="$2" login="$3" password="$4"

  cat > "${GOST_CONFIG}" <<EOF
services:
  - name: local-socks5
    addr: ":1080"
    handler:
      type: socks5
      chain: upstream
    listener:
      type: tcp

chains:
  - name: upstream
    hops:
      - name: hop-0
        nodes:
          - name: external
            addr: ${ip}:${port}
            connector:
              type: socks5
              auth:
                username: "${login}"
                password: "${password}"
            dialer:
              type: tcp
EOF
}

# --- Команды ---
set_proxy() {
  local ip="$1" port="$2" login="$3" password="$4"

  validate_ip "${ip}"
  validate_port "порт прокси" "${port}"

  save_upstream "${ip}" "${port}" "${login}" "${password}"
  write_proxy_config "${ip}" "${port}" "${login}" "${password}"

  systemctl restart gost

  echo "Upstream прокси задан: ${ip}:${port}"
  echo "Proxy mode: ON (трафик идёт через upstream SOCKS5)"
}

proxy_on() {
  load_upstream
  write_proxy_config "${UPSTREAM_IP}" "${UPSTREAM_PORT}" "${UPSTREAM_LOGIN}" "${UPSTREAM_PASSWORD}"
  systemctl restart gost
  echo "Proxy mode: ON (трафик идёт через ${UPSTREAM_IP}:${UPSTREAM_PORT})"
}

proxy_off() {
  write_direct_config
  systemctl restart gost
  echo "Proxy mode: OFF (direct — весь трафик напрямую)"
}

show_status() {
  local svc_state="inactive"
  local mode="UNKNOWN"

  if systemctl is-active --quiet gost; then
    svc_state="active"
  fi

  # Определяем режим по наличию chain в конфиге
  if [ -f "${GOST_CONFIG}" ] && grep -q "chain:" "${GOST_CONFIG}" 2>/dev/null; then
    mode="PROXY"
  else
    mode="DIRECT"
  fi

  echo "gost_service=${svc_state}"
  echo "mode=${mode}"

  if [ -f "${GOST_UPSTREAM_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${GOST_UPSTREAM_FILE}"
    echo "upstream=${UPSTREAM_IP:-}:${UPSTREAM_PORT:-}"
  else
    echo "upstream=не задан"
  fi

  echo "state=${mode}"

  if [ "${svc_state}" != "active" ]; then
    return 1
  fi
}

main() {
  require_root

  if [ "$#" -lt 1 ]; then
    usage
    exit 1
  fi

  local mode="$1"

  case "$mode" in
    set)
      if [ "$#" -ne 5 ]; then
        usage
        exit 1
      fi
      set_proxy "$2" "$3" "$4" "$5"
      ;;

    off)
      if [ "$#" -ne 1 ]; then
        usage
        exit 1
      fi
      proxy_off
      ;;

    on)
      if [ "$#" -ne 1 ]; then
        usage
        exit 1
      fi
      proxy_on
      ;;

    status)
      if [ "$#" -ne 1 ]; then
        usage
        exit 1
      fi
      show_status
      ;;

    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
