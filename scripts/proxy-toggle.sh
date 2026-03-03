#!/usr/bin/env bash
# =============================================================================
# Управление redsocks прокси: включение, выключение, статус
# Использование: proxy-toggle.sh <on|off|status>
# =============================================================================
set -euo pipefail

usage() {
  echo "Использование: $0 <off|on|status>" >&2
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

  if [ "$#" -ne 1 ]; then
    usage
    exit 1
  fi

  local mode="$1"

  case "$mode" in
    off)
      remove_output_jump_all
      systemctl stop redsocks || true
      save_rules
      echo "Proxy mode: OFF (bypass enabled)"
      ;;

    on)
      iptables -t nat -N REDSOCKS 2>/dev/null || true
      add_output_jump_once
      redsocks -t -c /etc/redsocks.conf
      systemctl start redsocks
      save_rules
      echo "Proxy mode: ON (traffic redirected through redsocks)"
      ;;

    status)
      show_status
      ;;

    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
