#!/usr/bin/env bash
# =============================================================================
# Оркестратор обновления cliproxy-api
# Вызывается cliproxy-api-updater.service (systemd oneshot, 05:00)
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="cliproxy-api.service"
BIN="/opt/cliproxy-api/cli-proxy-api"
SELFUPDATE="${SCRIPT_DIR}/cliproxy-api-selfupdate.sh"
ROLLBACK="${SCRIPT_DIR}/cliproxy-api-rollback.sh"
HEALTH_PORT="8317"
HEALTH_TIMEOUT=30

log()  { echo "[cliproxy-api-update] $*"; }

get_version() {
  "${BIN}" 2>&1 | head -n 1 2>/dev/null || echo "unknown"
}

health_check() {
  log "Health-check: порт ${HEALTH_PORT}, ждём до ${HEALTH_TIMEOUT}s..."
  local i
  for i in $(seq 1 "${HEALTH_TIMEOUT}"); do
    if timeout 2 bash -c "echo > /dev/tcp/localhost/${HEALTH_PORT}" 2>/dev/null; then
      log "Health-check OK (${i}s)"
      return 0
    fi
    sleep 1
  done
  log "Health-check FAILED"
  return 1
}

# --- Предварительные проверки ---
[ -f "${BIN}" ]        || { log "WARN: binary не найден: ${BIN}"; exit 0; }
[ -x "${SELFUPDATE}" ] || { log "WARN: selfupdate script не найден: ${SELFUPDATE}"; exit 0; }

# --- Версия до обновления ---
VERSION_BEFORE="$(get_version)"
log "Версия до обновления: ${VERSION_BEFORE}"

# --- Selfupdate (soft-fail: скрипт сам логирует ошибки и выходит с 0) ---
log "Запуск selfupdate..."
"${SELFUPDATE}" || log "WARN: selfupdate завершился с предупреждением"

# --- Версия после обновления ---
VERSION_AFTER="$(get_version)"
log "Версия после обновления: ${VERSION_AFTER}"

# --- Если версия не изменилась — ничего не делаем ---
if [ "${VERSION_BEFORE}" = "${VERSION_AFTER}" ]; then
  log "Актуальная версия, рестарт не нужен"
  exit 0
fi

log "Обнаружено обновление: ${VERSION_BEFORE} → ${VERSION_AFTER}"
log "Перезапуск ${SERVICE}..."
if ! systemctl restart "${SERVICE}"; then
  log "ERROR: рестарт не удался"
  exit 1
fi

# --- Health-check ---
if ! health_check; then
  log "Health-check не прошёл — запускаем откат..."
  if [ -x "${ROLLBACK}" ]; then
    "${ROLLBACK}" || log "WARN: rollback script завершился с ошибкой"
  else
    log "WARN: rollback script не найден: ${ROLLBACK}"
  fi
  exit 1
fi

log "Обновление успешно: ${VERSION_BEFORE} → ${VERSION_AFTER}"
exit 0
