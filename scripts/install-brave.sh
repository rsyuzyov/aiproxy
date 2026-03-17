#!/usr/bin/env bash
# =============================================================================
# Установка Brave Browser на Debian
# Источник: https://brave.com/linux/
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[brave]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[brave]${NC} $*"; }
log_error()   { echo -e "${RED}[brave]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[brave] OK:${NC} $*"; }

BRAVE_KEYRING="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
BRAVE_SOURCES="/etc/apt/sources.list.d/brave-browser-release.list"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_deps() {
  log_info "Устанавливаю зависимости..."
  apt-get update -qq
  apt-get install -y curl gnupg apt-transport-https
}

add_brave_repo() {
  log_info "Добавляю репозиторий Brave Browser..."

  # Скачать и добавить GPG ключ
  curl -fsSL "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" \
    -o "${BRAVE_KEYRING}"

  # Добавить репозиторий
  echo "deb [signed-by=${BRAVE_KEYRING}] https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > "${BRAVE_SOURCES}"

  apt-get update -qq
  log_success "Репозиторий Brave добавлен"
}

install_brave() {
  if dpkg -l brave-browser &>/dev/null 2>&1; then
    log_info "Brave Browser уже установлен, обновляю..."
    apt-get install -y --only-upgrade brave-browser
  else
    log_info "Устанавливаю Brave Browser..."
    apt-get install -y brave-browser
  fi

  local ver
  ver="$(brave-browser --version 2>/dev/null | awk '{print $3}' || echo 'неизвестна')"
  log_success "Brave Browser установлен: ${ver}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root
  install_deps
  add_brave_repo
  install_brave
}

main "$@"
