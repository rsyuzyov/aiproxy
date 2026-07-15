#!/usr/bin/env bash
# =============================================================================
# Управление sing-box в режиме TUN-клиента (прозрачное проксирование всего
# исходящего трафика через внешний SOCKS5, кроме loopback/LAN).
#
#   singbox-toggle.sh set <ip> <port> [user] [pass]  — задать upstream + включить прокси
#   singbox-toggle.sh on                              — включить прокси (upstream уже задан)
#   singbox-toggle.sh off                             — direct-режим (без прокси)
#   singbox-toggle.sh status                          — текущее состояние
# =============================================================================
set -euo pipefail

CONFIG="/etc/sing-box/config.json"
SERVICE="sing-box"

GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'; NC=$'\033[0m'
log()  { echo -e "${GREEN}[singbox]${NC} $*"; }
warn() { echo -e "${YELLOW}[singbox]${NC} $*"; }
err()  { echo -e "${RED}[singbox]${NC} $*" >&2; }

[ "${EUID}" -eq 0 ] || { err "Запусти от root"; exit 1; }
[ -f "${CONFIG}" ]   || { err "Нет конфига ${CONFIG} (установи sing-box в client-режиме)"; exit 1; }

need_jq() { command -v jq >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq jq; }; }

apply() {
  # apply <jq-программа>
  need_jq
  local tmp; tmp="$(mktemp)"
  jq "$1" "${CONFIG}" > "${tmp}"
  if ! sing-box check -c "${tmp}" >/dev/null 2>&1; then
    err "Конфиг не прошёл проверку, откат"; rm -f "${tmp}"; return 1
  fi
  mv "${tmp}" "${CONFIG}"
  systemctl restart "${SERVICE}"
  sleep 1
  systemctl is-active --quiet "${SERVICE}" && log "sing-box перезапущен" || { err "sing-box не поднялся"; systemctl status "${SERVICE}" --no-pager || true; return 1; }
}

cmd="${1:-status}"
case "${cmd}" in
  set)
    IP="${2:?нужен ip}"; PORT="${3:?нужен port}"; USER="${4:-}"; PASS="${5:-}"
    apply "
      (.outbounds[] | select(.tag==\"proxy\")) |= (
        .server=\"${IP}\" | .server_port=(${PORT}|tonumber) |
        ( if \"${USER}\" == \"\" then del(.username,.password)
          else .username=\"${USER}\" | .password=\"${PASS}\" end )
      )
      | .route.final=\"proxy\" | .dns.final=\"dns-proxy\"
    "
    log "upstream задан: ${IP}:${PORT}$([ -n "${USER}" ] && echo " (auth)"), прокси ВКЛ"
    ;;
  on)
    apply '.route.final="proxy" | .dns.final="dns-proxy"'
    log "прокси ВКЛ"
    ;;
  off)
    apply '.route.final="direct" | .dns.final="dns-direct"'
    log "прокси ВЫКЛ (direct)"
    ;;
  status)
    need_jq
    mode="$(jq -r '.route.final' "${CONFIG}")"
    srv="$(jq -r '(.outbounds[]|select(.tag=="proxy"))|"\(.server):\(.server_port)"' "${CONFIG}")"
    auth="$(jq -r '(.outbounds[]|select(.tag=="proxy"))|if .username then "auth" else "no-auth" end' "${CONFIG}")"
    echo "режим:    ${mode}  (proxy=через upstream, direct=напрямую)"
    echo "upstream: ${srv} (${auth})"
    printf "служба:   "; systemctl is-active "${SERVICE}"
    echo -n "exit IP:  "; curl -4 -sS --max-time 8 https://ifconfig.me 2>/dev/null || echo "n/a"; echo
    ;;
  *)
    err "Неизвестная команда: ${cmd}"
    echo "Использование: $0 {set <ip> <port> [user] [pass] | on | off | status}"
    exit 1
    ;;
esac
