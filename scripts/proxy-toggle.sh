#!/usr/bin/env bash
# =============================================================================
# Управление redsocks прокси: set/on/off/status
# Использование:
#   proxy-toggle.sh set <proxy_ip> <proxy_port> <login> <password> [local_port]
#   proxy-toggle.sh <on|off|status>
# =============================================================================
set -euo pipefail

usage() {
  cat >&2 <<EOF
Использование:
  $0 set <proxy_ip> <proxy_port> <login> <password> [local_port]
  $0 <off|on|status>
EOF
}

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo "Запустите от имени root" >&2
    exit 1
  fi
}

save_rules() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null
  elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
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

remove_output_jump_all() {
  while iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null; do
    iptables -t nat -D OUTPUT -p tcp -j REDSOCKS
  done
}

add_output_jump_once() {
  if ! iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null; then
    iptables -t nat -A OUTPUT -p tcp -j REDSOCKS
  fi
}

write_redsocks_conf() {
  local ip="$1" port="$2" login="$3" password="$4" local_port="$5"

  cat > /etc/redsocks.conf <<EOF
base {
  log_debug = off;
  log_info = on;
  daemon = on;
  redirector = iptables;
}

redsocks {
  local_ip = 127.0.0.1;
  local_port = ${local_port};
  ip = ${ip};
  port = ${port};
  type = socks5;
  login = "${login}";
  password = "${password}";
}
EOF

  chmod 600 /etc/redsocks.conf
}

setup_iptables_chain() {
  local ip="$1" local_port="$2"

  iptables -t nat -N REDSOCKS 2>/dev/null || true
  iptables -t nat -F REDSOCKS

  local bypass_nets=(
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "224.0.0.0/4"
    "240.0.0.0/4"
  )

  for net in "${bypass_nets[@]}"; do
    iptables -t nat -A REDSOCKS -d "${net}" -j RETURN
  done

  iptables -t nat -A REDSOCKS -d "${ip}/32" -j RETURN
  iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports "${local_port}"

  remove_output_jump_all
  add_output_jump_once

  save_rules
}

set_proxy() {
  local ip="$1" port="$2" login="$3" password="$4" local_port="$5"

  validate_ip "${ip}"
  validate_port "порт прокси" "${port}"
  validate_port "локальный порт" "${local_port}"

  write_redsocks_conf "${ip}" "${port}" "${login}" "${password}" "${local_port}"
  redsocks -t -c /etc/redsocks.conf

  setup_iptables_chain "${ip}" "${local_port}"

  systemctl enable redsocks >/dev/null 2>&1 || true
  systemctl restart redsocks

  echo "Proxy config updated: ${ip}:${port} (local ${local_port})"
  echo "Proxy mode: ON (traffic redirected through redsocks)"
}

show_status() {
  local svc_state="inactive"
  local jump_state="absent"
  local final_state=""

  if systemctl is-active --quiet redsocks; then
    svc_state="active"
  fi

  if iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null; then
    jump_state="present"
  fi

  if [ "$svc_state" = "active" ] && [ "$jump_state" = "present" ]; then
    final_state="ACTIVE"
  elif [ "$svc_state" = "inactive" ] && [ "$jump_state" = "absent" ]; then
    final_state="BYPASS"
  else
    final_state="BROKEN"
  fi

  echo "redsocks_service=${svc_state}"
  echo "output_jump_redsocks=${jump_state}"
  echo "state=${final_state}"

  if [ "$final_state" = "BROKEN" ]; then
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
      if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
        usage
        exit 1
      fi
      local proxy_ip="$2"
      local proxy_port="$3"
      local proxy_login="$4"
      local proxy_password="$5"
      local local_port="${6:-12345}"
      set_proxy "${proxy_ip}" "${proxy_port}" "${proxy_login}" "${proxy_password}" "${local_port}"
      ;;

    off)
      if [ "$#" -ne 1 ]; then
        usage
        exit 1
      fi
      remove_output_jump_all
      systemctl stop redsocks || true
      save_rules
      echo "Proxy mode: OFF (bypass enabled)"
      ;;

    on)
      if [ "$#" -ne 1 ]; then
        usage
        exit 1
      fi
      iptables -t nat -N REDSOCKS 2>/dev/null || true
      add_output_jump_once
      redsocks -t -c /etc/redsocks.conf
      systemctl start redsocks
      save_rules
      echo "Proxy mode: ON (traffic redirected through redsocks)"
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
