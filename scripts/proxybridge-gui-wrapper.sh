#!/usr/bin/env bash
# Обёртка для ProxyBridgeGUI: останавливает демон, запускает GUI, по выходу — стартует демон
set -euo pipefail

SERVICE="proxybridge"

# Останавливаем systemd-сервис если запущен
if systemctl is-active --quiet "${SERVICE}" 2>/dev/null; then
  systemctl stop "${SERVICE}"
fi

# Запускаем GUI и ждём завершения
/usr/local/bin/ProxyBridgeGUI "$@" || true

# Возвращаем сервис
systemctl start "${SERVICE}"
