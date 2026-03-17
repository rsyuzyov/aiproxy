#!/usr/bin/env bash
# Парсит /etc/proxybridge/config и экспортирует PROXYBRIDGE_ARGS
# Вызывается через source из proxybridge.service
CONFIG="/etc/proxybridge/config"
RULE_ARGS=""
PROXY=""
if [ -f "${CONFIG}" ]; then
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    if [[ "$line" == RULE=* ]]; then
      RULE_ARGS="${RULE_ARGS} --rule ${line#RULE=}"
    elif [[ "$line" == PROXY=* ]]; then
      PROXY="${line#PROXY=}"
    fi
  done < "${CONFIG}"
fi
if [ -n "${PROXY}" ]; then
  export PROXYBRIDGE_ARGS="--proxy ${PROXY} ${RULE_ARGS}"
else
  export PROXYBRIDGE_ARGS="${RULE_ARGS}"
fi
