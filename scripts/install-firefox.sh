#!/usr/bin/env bash
# =============================================================================
# Установка Firefox ESR на Debian
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[firefox]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[firefox]${NC} $*"; }
log_error()   { echo -e "${RED}[firefox]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[firefox] OK:${NC} $*"; }

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_firefox() {
  log_info "Обновляю пакетный менеджер..."
  apt-get update -qq

  # Firefox ESR доступен в официальных репозиториях Debian.
  # Используем dpkg-query со статусом ii (installed), потому что
  # `dpkg -l firefox-esr` возвращает 0 даже при статусе 'un' (unpack/not-installed),
  # что приводило к ложному срабатыванию ветки --only-upgrade.
  local pkg_status
  pkg_status="$(dpkg-query -W -f='${Status}' firefox-esr 2>/dev/null || true)"

  if [ "${pkg_status}" = "install ok installed" ]; then
    log_info "Firefox ESR уже установлен, обновляю до актуальной версии..."
    apt-get install -y -qq --only-upgrade firefox-esr
  else
    log_info "Firefox ESR не установлен (статус: '${pkg_status:-отсутствует}'), выполняю установку..."
    apt-get install -y -qq firefox-esr
  fi

  # --- Self-check: убеждаемся, что пакет действительно установлен ---
  local final_status
  final_status="$(dpkg-query -W -f='${Status}' firefox-esr 2>/dev/null || true)"
  if [ "${final_status}" != "install ok installed" ]; then
    log_error "Firefox ESR не установлен после попытки установки (статус: '${final_status}')"
    exit 1
  fi

  local ver
  ver="$(firefox-esr --version 2>/dev/null | awk '{print $3}' || echo 'неизвестна')"
  log_success "Firefox ESR установлен: ${ver}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root
  install_firefox
}

main "$@"
