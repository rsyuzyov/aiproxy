#!/usr/bin/env bash
# =============================================================================
# Установка и базовая подготовка redsocks (без параметров прокси)
# Использование:
#   setup-redsocks.sh
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[redsocks]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[redsocks]${NC} $*"; }
log_error()   { echo -e "${RED}[redsocks]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[redsocks] OK:${NC} $*"; }

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_TOGGLE="${SCRIPTS_DIR}/proxy-toggle.sh"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

prepare_noninteractive_apt() {
  export DEBIAN_FRONTEND=noninteractive

  # Убрать интерактивные вопросы iptables-persistent в контейнерах/CI
  if command -v debconf-set-selections &>/dev/null; then
    echo 'iptables-persistent iptables-persistent/autosave_v4 boolean false' | debconf-set-selections || true
    echo 'iptables-persistent iptables-persistent/autosave_v6 boolean false' | debconf-set-selections || true
  fi
}

install_redsocks_tools() {
  prepare_noninteractive_apt

  log_info "Устанавливаю необходимые пакеты redsocks/iptables..."
  apt-get update -qq
  apt-get install -y redsocks iptables netfilter-persistent iptables-persistent
  log_success "Пакеты redsocks/iptables установлены"
}

ensure_local_scripts_executable() {
  log_info "Проверяю локальные скрипты в каталоге репозитория..."

  chmod +x "${PROXY_TOGGLE}"
  chmod +x "${SCRIPTS_DIR}/setup-redsocks.sh"

  log_success "Локальные скрипты готовы к запуску из ${SCRIPTS_DIR}"
}

prepare_redsocks_service() {
  # Включаем unit, но старт/стоп делаем через proxy-toggle.sh
  systemctl enable redsocks >/dev/null 2>&1 || true
  log_success "Служба redsocks подготовлена"
}

set_initial_bypass_mode() {
  log_info "Применяю начальный режим прокси: OFF (как ${PROXY_TOGGLE} off)..."
  "${PROXY_TOGGLE}" off
}

show_usage() {
  cat <<EOF
Использование: $0

Скрипт устанавливает необходимые пакеты для redsocks и подготавливает службу.
Параметры SOCKS5 задаются отдельно командой:
  ${PROXY_TOGGLE} set <proxy_ip> <proxy_port> <login> <password> [local_port]

Управление режимом прокси:
  ${PROXY_TOGGLE} on|off|status
EOF
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  if [ "$#" -ne 0 ]; then
    show_usage
    exit 1
  fi

  install_redsocks_tools
  ensure_local_scripts_executable
  prepare_redsocks_service
  set_initial_bypass_mode

  echo ""
  log_success "redsocks и инструменты iptables установлены"
  log_info "Задайте параметры прокси командой:"
  log_info "  ${PROXY_TOGGLE} set <ip> <port> <login> <password> [local_port]"
  log_info "Управление прокси:"
  log_info "  ${PROXY_TOGGLE} on     — включить"
  log_info "  ${PROXY_TOGGLE} off    — выключить"
  log_info "  ${PROXY_TOGGLE} status — статус"
}

main "$@"
