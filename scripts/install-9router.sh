#!/usr/bin/env bash
# =============================================================================
# Установка службы 9router (npm-пакет)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[9router]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[9router]${NC} $*"; }
log_error()   { echo -e "${RED}[9router]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[9router] OK:${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_TEMPLATE="${SCRIPT_DIR}/../configs/systemd/9router.service"
SYSTEMD_DIR="${SCRIPT_DIR}/../configs/systemd"
SERVICE_NAME="9router"
NODE_VERSION="20"  # LTS версия Node.js

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_nodejs() {
  if command -v node &>/dev/null; then
    local ver
    ver="$(node --version | tr -d 'v' | cut -d. -f1)"
    if [ "${ver}" -ge "${NODE_VERSION}" ]; then
      log_info "Node.js уже установлен: $(node --version)"
      return
    fi
    log_warn "Установлена старая версия Node.js $(node --version), требуется >= v${NODE_VERSION}"
  fi

  log_info "Устанавливаю Node.js ${NODE_VERSION}.x через NodeSource..."

  apt-get update -qq
  apt-get install -y -qq curl gnupg

  # NodeSource репозиторий
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
  apt-get install -y -qq nodejs

  log_success "Node.js установлен: $(node --version)"
  log_success "npm: $(npm --version)"
}

install_9router() {
  log_info "Устанавливаю 9router глобально через npm..."

  if command -v 9router &>/dev/null; then
    log_info "9router уже установлен, обновляю..."
    npm install -g 9router || log_warn "Не удалось обновить 9router"
  else
    npm install -g 9router
  fi

  local bin_path
  bin_path="$(which 9router 2>/dev/null || echo '/usr/bin/9router')"
  log_success "9router установлен: ${bin_path}"
  log_info "Версия: $(9router --version 2>/dev/null || echo 'неизвестна')"
}

install_systemd_unit() {
  log_info "Устанавливаю systemd unit..."

  if [ ! -f "${SYSTEMD_TEMPLATE}" ]; then
    log_error "Не найден шаблон unit-файла: ${SYSTEMD_TEMPLATE}"
    exit 1
  fi

  local bin_path
  bin_path="$(which 9router 2>/dev/null || echo '/usr/bin/9router')"

  sed "s|__BIN_PATH__|${bin_path}|g" "${SYSTEMD_TEMPLATE}" > "/etc/systemd/system/${SERVICE_NAME}.service"

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"
  log_success "Systemd unit установлен и включён"
}

install_updater_timer() {
  log_info "Устанавливаю таймер автообновления..."

  local update_bin="${SCRIPT_DIR}/9router-update.sh"
  local selfupdate_bin="${SCRIPT_DIR}/9router-selfupdate.sh"
  local updater_svc="${SYSTEMD_DIR}/9router-updater.service"
  local updater_tmr="${SYSTEMD_DIR}/9router-updater.timer"

  if [ ! -f "${updater_svc}" ] || [ ! -f "${updater_tmr}" ]; then
    log_warn "Шаблоны таймера не найдены в ${SYSTEMD_DIR}, пропускаю"
    return
  fi

  chmod +x "${update_bin}" "${selfupdate_bin}" 2>/dev/null || true

  sed -e "s|__9ROUTER_UPDATE_BIN__|${update_bin}|g" \
    "${updater_svc}" > "/etc/systemd/system/9router-updater.service"

  cp "${updater_tmr}" "/etc/systemd/system/9router-updater.timer"

  systemctl daemon-reload
  systemctl enable --now "9router-updater.timer"
  log_success "Таймер обновления установлен (ежедневно в 05:00)"
  log_info "Следующий запуск: $(systemctl show -P NextElapseUSecRealtime 9router-updater.timer 2>/dev/null || echo 'см. systemctl list-timers')"
}


# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  install_nodejs
  install_9router
  install_systemd_unit
  install_updater_timer

  # Запустить службу
  systemctl start "${SERVICE_NAME}.service"
  sleep 2

  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    log_success "Служба ${SERVICE_NAME} запущена!"
    log_info "Веб-интерфейс: http://localhost:20128"
  else
    log_warn "Служба не запустилась. Проверьте: journalctl -u ${SERVICE_NAME} -n 20"
  fi
}

main "$@"
