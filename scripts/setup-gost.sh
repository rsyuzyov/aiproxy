#!/usr/bin/env bash
# =============================================================================
# Установка gost (GO Simple Tunnel)
# https://github.com/go-gost/gost
#
# Устанавливает gost-бинарник, конфиг и systemd-юнит.
# При установке запускается в direct-режиме (без upstream прокси).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs"

GREEN="${GREEN:-$'\033[0;32m'}"
YELLOW="${YELLOW:-$'\033[1;33m'}"
RED="${RED:-$'\033[0;31m'}"
NC="${NC:-$'\033[0m'}"

log_info()    { echo -e "${GREEN}[gost]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[gost]${NC} $*"; }
log_error()   { echo -e "${RED}[gost]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[gost] OK:${NC} $*"; }

GOST_TOGGLE="${SCRIPT_DIR}/gost-toggle.sh"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

# --- Установка бинарника gost ---
install_gost_binary() {
  if command -v gost &>/dev/null; then
    local current_ver
    current_ver=$(gost -V 2>&1 | head -1 || echo "unknown")
    log_info "gost уже установлен: ${current_ver}"
    log_info "Переустанавливаю последнюю версию..."
  fi

  log_info "Скачиваю и устанавливаю gost..."
  if ! bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install; then
    log_error "Не удалось установить gost"
    exit 1
  fi

  if ! command -v gost &>/dev/null; then
    log_error "Бинарник gost не найден после установки"
    exit 1
  fi

  local installed_ver
  installed_ver=$(gost -V 2>&1 | head -1 || echo "unknown")
  log_success "gost установлен: ${installed_ver}"
}

# --- Копирование конфигурации ---
install_config() {
  local config_src="${CONFIGS_DIR}/gost/config-direct.yaml"
  if [ ! -f "${config_src}" ]; then
    log_error "Не найден конфиг: ${config_src}"
    exit 1
  fi

  mkdir -p /etc/gost

  if [ ! -f /etc/gost/config.yaml ]; then
    sed 's/\r$//' "${config_src}" > /etc/gost/config.yaml
    log_success "Конфиг установлен: /etc/gost/config.yaml (direct-режим)"
  else
    log_info "Конфиг уже существует, пропускаю: /etc/gost/config.yaml"
  fi
}

# --- Установка systemd-юнита ---
install_service() {
  local service_src="${CONFIGS_DIR}/systemd/gost.service"
  if [ ! -f "${service_src}" ]; then
    log_error "Не найден systemd-юнит: ${service_src}"
    exit 1
  fi

  log_info "Устанавливаю systemd-сервис gost..."
  sed 's/\r$//' "${service_src}" > /etc/systemd/system/gost.service
  systemctl daemon-reload
  systemctl enable gost
  log_success "Сервис установлен: /etc/systemd/system/gost.service"
}

# --- Запуск ---
start_service() {
  log_info "Запускаю gost..."
  systemctl start gost
  sleep 1

  if systemctl is-active --quiet gost; then
    log_success "gost запущен (direct-режим — весь трафик напрямую)"
  else
    log_warn "gost не запустился, проверь: journalctl -u gost -n 20"
  fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  if [ "$#" -ne 0 ]; then
    echo "Использование: $0"
    echo ""
    echo "Устанавливает gost и запускает в direct-режиме."
    echo "Upstream прокси задаётся отдельно:"
    echo "  ${GOST_TOGGLE} set <ip> <port> <login> <password>"
    exit 1
  fi

  install_gost_binary
  install_config
  install_service
  start_service

  echo ""
  log_info "╔══════════════════════════════════════════════════════╗"
  log_info "║  gost работает в режиме DIRECT (без прокси)        ║"
  log_info "║  SOCKS5 доступен на 0.0.0.0:1080 без авторизации   ║"
  log_info "╚══════════════════════════════════════════════════════╝"
  log_info ""
  log_info "Чтобы включить upstream прокси:"
  log_info "  ${GOST_TOGGLE} set <ip> <port> <login> <password>"
  log_info ""
  log_info "Управление:"
  log_info "  ${GOST_TOGGLE} on      — включить upstream прокси"
  log_info "  ${GOST_TOGGLE} off     — отключить (direct-режим)"
  log_info "  ${GOST_TOGGLE} status  — текущий статус"
  log_info ""
  log_info "Полезные команды:"
  log_info "  systemctl status gost"
  log_info "  systemctl restart gost"
  log_info "  journalctl -u gost -f"
}

main "$@"
