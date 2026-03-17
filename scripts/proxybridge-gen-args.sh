#!/usr/bin/env bash
# Генерирует /run/proxybridge.env из /etc/proxybridge/config
# Вызывается из proxybridge.service (ExecStartPre)
set -euo pipefail

CONFIG="/etc/proxybridge/config"

if [ ! -f "${CONFIG}" ]; then
  echo "PROXYBRIDGE_ARGS=" > /run/proxybridge.env
  exit 0
fi

RULE_ARGS=""
while IFS= read -r line; do
  line="${line%%$'\r'}"  # убираем \r если есть
  [ -z "$line" ] && continue
  [[ "$line" == \#* ]] && continue
  if [[ "$line" == RULE=* ]]; then
    RULE_ARGS="${RULE_ARGS} --rule \"${line#RULE=}\""
  fi
done < "${CONFIG}"

PROXY=""
while IFS= read -r line; do
  line="${line%%$'\r'}"
  [ -z "$line" ] && continue
  [[ "$line" == \#* ]] && continue
  if [[ "$line" == PROXY=* ]]; then
    PROXY="${line#PROXY=}"
  fi
done < "${CONFIG}"

if [ -n "${PROXY}" ]; then
  echo "PROXYBRIDGE_ARGS=--proxy ${PROXY} ${RULE_ARGS}" > /run/proxybridge.env
else
  echo "PROXYBRIDGE_ARGS=${RULE_ARGS}" > /run/proxybridge.env
fi
