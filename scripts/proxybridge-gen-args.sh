#!/usr/bin/env bash
# Парсит /etc/proxybridge/config.ini (формат ProxyBridgeGUI) и экспортирует PROXYBRIDGE_ARGS
# Вызывается через source из proxybridge.service
CONFIG="/etc/proxybridge/config.ini"

# --- Маппинг enum из ProxyBridge.h ---
PROXY_TYPES=("http" "socks5")
RULE_ACTIONS=("PROXY" "DIRECT" "BLOCK")
RULE_PROTOCOLS=("TCP" "UDP" "BOTH")

PROXY_IP=""
PROXY_PORT=""
PROXY_TYPE_NUM=""
PROXY_USER=""
PROXY_PASS=""
DNS_VIA_PROXY=""
RULE_ARGS=""

if [ -f "${CONFIG}" ]; then
  section=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue

    # Определяем секцию
    if [[ "$line" == "[SETTINGS]" ]]; then section="settings"; continue; fi
    if [[ "$line" == "[RULES]" ]]; then section="rules"; continue; fi
    [[ "$line" == \[* ]] && section=""; continue

    if [[ "$section" == "settings" ]]; then
      key="${line%%=*}"
      val="${line#*=}"
      case "$key" in
        ip)   PROXY_IP="$val" ;;
        port) PROXY_PORT="$val" ;;
        type) PROXY_TYPE_NUM="$val" ;;
        user) PROXY_USER="$val" ;;
        pass) PROXY_PASS="$val" ;;
        dns)  DNS_VIA_PROXY="$val" ;;
      esac

    elif [[ "$section" == "rules" ]]; then
      # Формат: id|protocol|action|enabled|process|hosts|ports
      IFS='|' read -r _id r_proto r_action r_enabled r_proc r_hosts r_ports <<< "$line"

      # Пропускаем отключённые правила
      [[ "$r_enabled" != "1" ]] && continue

      proto="${RULE_PROTOCOLS[$r_proto]:-BOTH}"
      action="${RULE_ACTIONS[$r_action]:-DIRECT}"
      proc="${r_proc:-*}"
      hosts="${r_hosts:-*}"
      ports="${r_ports:-*}"

      RULE_ARGS="${RULE_ARGS} --rule ${proc}:${hosts}:${ports}:${proto}:${action}"
    fi
  done < "${CONFIG}"
fi

# --- Собираем --proxy ---
PROXY_ARG=""
if [ -n "${PROXY_IP}" ] && [ -n "${PROXY_PORT}" ]; then
  ptype="${PROXY_TYPES[$PROXY_TYPE_NUM]:-socks5}"
  PROXY_ARG="--proxy ${ptype}://${PROXY_IP}:${PROXY_PORT}"
  if [ -n "${PROXY_USER}" ] && [ -n "${PROXY_PASS}" ]; then
    PROXY_ARG="${PROXY_ARG}:${PROXY_USER}:${PROXY_PASS}"
  fi
fi

# --- Собираем --dns-via-proxy ---
DNS_ARG=""
if [ -n "${DNS_VIA_PROXY}" ]; then
  if [[ "${DNS_VIA_PROXY}" == "1" ]]; then
    DNS_ARG="--dns-via-proxy true"
  else
    DNS_ARG="--dns-via-proxy false"
  fi
fi

export PROXYBRIDGE_ARGS="${PROXY_ARG} ${RULE_ARGS} ${DNS_ARG}"
# Убираем лишние пробелы
PROXYBRIDGE_ARGS="$(echo "$PROXYBRIDGE_ARGS" | xargs)"
export PROXYBRIDGE_ARGS
