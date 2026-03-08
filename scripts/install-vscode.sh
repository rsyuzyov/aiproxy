#!/usr/bin/env bash
# =============================================================================
# Установка Visual Studio Code на Debian/Ubuntu
# Источник: https://code.visualstudio.com/docs/setup/linux
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[vscode]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[vscode]${NC} $*"; }
log_error()   { echo -e "${RED}[vscode]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[vscode] OK:${NC} $*"; }

VSCODE_KEYRING="/usr/share/keyrings/packages.microsoft.gpg"
VSCODE_SOURCES="/etc/apt/sources.list.d/vscode.list"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_deps() {
  log_info "Устанавливаю зависимости..."
  apt-get update -qq
  apt-get install -y -qq curl gpg apt-transport-https ca-certificates
}

add_vscode_repo() {
  log_info "Добавляю репозиторий Microsoft VS Code..."

  # Скачать и добавить GPG ключ Microsoft
  curl -fsSL "https://packages.microsoft.com/keys/microsoft.asc" \
    | gpg --dearmor -o "${VSCODE_KEYRING}"

  # Добавить репозиторий
  echo "deb [arch=$(dpkg --print-architecture) signed-by=${VSCODE_KEYRING}] https://packages.microsoft.com/repos/code stable main" \
    > "${VSCODE_SOURCES}"

  apt-get update -qq
  log_success "Репозиторий VS Code добавлен"
}

install_vscode() {
  if dpkg -l code &>/dev/null 2>&1; then
    log_info "VS Code уже установлен, обновляю..."
    apt-get install -y -qq --only-upgrade code
  else
    log_info "Устанавливаю Visual Studio Code..."
    apt-get install -y -qq code
  fi

  local ver
  ver="$(code --version 2>/dev/null | head -1 || echo 'неизвестна')"
  log_success "Visual Studio Code установлен: ${ver}"
  log_info "Запуск: code (или через меню приложений)"
  log_warn "Для работы GUI требуется xrdp или другой способ доступа к рабочему столу"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root
  install_deps
  add_vscode_repo
  install_vscode
}

main "$@"
