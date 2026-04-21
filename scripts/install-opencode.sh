#!/usr/bin/env bash
# =============================================================================
# Установка OpenCode (CLI + Desktop)
# https://opencode.ai/
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[opencode]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[opencode]${NC} $*"; }
log_error()   { echo -e "${RED}[opencode]${NC} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${BLUE}==>${NC}${BOLD} $*${NC}"; }
log_success() { echo -e "${GREEN}[opencode] OK:${NC} $*"; }

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_deps() {
  log_info "Устанавливаю зависимости..."
  apt-get update -qq
  apt-get install -y curl
}

# --- OpenCode CLI ---
install_opencode_cli() {
  log_step "Установка OpenCode CLI"

  log_info "Запускаю официальный установщик OpenCode..."
  curl -fsSL https://opencode.ai/install | bash

  # Проверяем типичные пути установки
  local bin_candidates=(
    "/root/.opencode/bin"
    "${HOME}/.opencode/bin"
    "/usr/local/bin"
  )
  for candidate in "${bin_candidates[@]}"; do
    if [ -f "${candidate}/opencode" ]; then
      log_success "OpenCode CLI установлен: ${candidate}/opencode"
      break
    fi
  done

  if command -v opencode &>/dev/null; then
    local ver
    ver="$(opencode --version 2>/dev/null || echo 'неизвестна')"
    log_success "OpenCode CLI готов! Версия: ${ver}"
  else
    log_warn "opencode не найден в PATH. Возможно, нужно перезайти в терминал."
    log_info "Попробуйте: source ~/.bashrc && opencode"
  fi
}

# --- OpenCode Desktop ---
install_opencode_desktop() {
  log_step "Установка OpenCode Desktop"

  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

  local deb_url
  case "${arch}" in
    amd64)  deb_url="https://opencode.ai/download/stable/linux-x64-deb" ;;
    arm64)  deb_url="https://opencode.ai/download/stable/linux-arm64-deb" ;;
    *)
      log_error "Архитектура ${arch} не поддерживается для OpenCode Desktop"
      return 1
      ;;
  esac

  local tmp_deb
  tmp_deb="$(mktemp /tmp/opencode-desktop-XXXXXX.deb)"

  log_info "Скачиваю OpenCode Desktop (${arch})..."
  curl -fSL -o "${tmp_deb}" "${deb_url}"

  log_info "Устанавливаю .deb пакет..."
  dpkg -i "${tmp_deb}" || apt-get install -f -y
  rm -f "${tmp_deb}"

  log_success "OpenCode Desktop установлен!"
  log_info "Запуск: opencode-desktop (или через меню приложений)"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root
  export DEBIAN_FRONTEND=noninteractive
  install_deps
  install_opencode_cli
  install_opencode_desktop
}

main "$@"
