#!/usr/bin/env bash
# =============================================================================
# Установка Google Antigravity IDE
# https://antigravity.google/
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${BLUE}==>${NC}${BOLD} $*${NC}"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# Проверяем Debian/Ubuntu
check_distro() {
  if ! command -v apt-get &>/dev/null; then
    log_error "Этот скрипт предназначен для Debian/Ubuntu (apt-based систем)."
    exit 1
  fi
}

install_antigravity() {
  log_step "Установка Google Antigravity IDE"

  export DEBIAN_FRONTEND=noninteractive

  log_info "Устанавливаем зависимости..."
  apt-get update -qq
  apt-get install -y curl gnupg apt-transport-https ca-certificates

  log_info "Добавляем GPG-ключ репозитория Antigravity..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.antigravity.google/apt/repository/signing-key.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/antigravity.gpg

  log_info "Добавляем репозиторий Antigravity..."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/antigravity.gpg] \
https://packages.antigravity.google/apt/repository stable main" \
    | tee /etc/apt/sources.list.d/antigravity.list > /dev/null

  log_info "Устанавливаем antigravity..."
  apt-get update -qq
  apt-get install -y antigravity

  log_success "Google Antigravity IDE установлен!"
  log_info "Запуск: antigravity (или через меню приложений)"
}

check_distro
install_antigravity
