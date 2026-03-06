#!/usr/bin/env bash
# =============================================================================
# Selfupdate 9router через npm
# Вызывается из 9router-update.sh
# =============================================================================
set -u

log() { echo "[9router-selfupdate] $*"; }

command -v npm    &>/dev/null || { log "WARN: npm не найден"; exit 0; }
command -v 9router &>/dev/null || { log "WARN: 9router не установлен"; exit 0; }

log "Запуск: npm install -g 9router..."
npm install -g 9router 2>&1
log "Готово"
exit 0
