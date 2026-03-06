#!/usr/bin/env bash
# =============================================================================
# Оркестратор обновления 9router
# Вызывается 9router-updater.service (systemd oneshot, 05:00)
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="9router.service"
SELFUPDATE="${SCRIPT_DIR}/9router-selfupdate.sh"
HEALTH_PORT="20128"
HEALTH_TIMEOUT=30

log() { echo "[9router-update] $*"; }

get_version() {
  9router --version 2>/dev/null || echo "unknown"
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
[ -x "${SELFUPDATE}" ]       || { log "WARN: selfupdate script не найден: ${SELFUPDATE}"; exit 0; }
command -v 9router &>/dev/null || { log "WARN: 9router не установлен"; exit 0; }

# --- Версия до обновления (нужна для возможного отката) ---
VERSION_BEFORE="$(get_version)"
log "Версия до обновления: ${VERSION_BEFORE}"

# --- Selfupdate ---
log "Запуск selfupdate..."
"${SELFUPDATE}" || log "WARN: selfupdate завершился с предупреждением"

# --- Версия после ---
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
  log "Health-check не прошёл — откат на версию ${VERSION_BEFORE}..."
  if [ "${VERSION_BEFORE}" != "unknown" ]; then
    npm install -g "9router@${VERSION_BEFORE}" 2>&1 || log "WARN: откат npm не удался"
  fi
  systemctl restart "${SERVICE}" || true
  exit 1
fi

log "Обновление успешно: ${VERSION_BEFORE} → ${VERSION_AFTER}"
exit 0
