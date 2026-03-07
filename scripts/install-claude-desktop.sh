#!/usr/bin/env bash
# =============================================================================
# Установка Claude Desktop на Linux (неофициальный порт)
# https://github.com/aaddrick/claude-desktop-debian
# Примечание: Официальный Claude Desktop доступен только для macOS и Windows.
# Этот скрипт использует неофициальный Debian-порт (перепаковка Windows-версии).
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${BLUE}==>${NC}${BOLD} $*${NC}"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

CLAUDE_DESKTOP_REPO="https://github.com/aaddrick/claude-desktop-debian"
APT_REPO_KEY_URL="https://raw.githubusercontent.com/aaddrick/claude-desktop-debian/main/signing-key.asc"
APT_REPO_URL="https://aaddrick.github.io/claude-desktop-debian/apt/"

check_distro() {
  if ! command -v apt-get &>/dev/null; then
    log_error "Этот скрипт предназначен для Debian/Ubuntu (apt-based систем)."
    exit 1
  fi

  # Предупреждение
  log_warn "⚠ Claude Desktop официально НЕ поддерживается на Linux."
  log_warn "  Используется неофициальный порт: ${CLAUDE_DESKTOP_REPO}"
  log_warn "  Проект перепаковывает официальное Windows-приложение для Debian."
  echo ""
}

install_dependencies() {
  log_info "Устанавливаем зависимости..."
  apt-get update -qq
  apt-get install -y -qq curl gnupg apt-transport-https ca-certificates

  # claude-desktop требует дополнительных зависимостей (Electron-приложение)
  apt-get install -y -qq \
    libgtk-3-0 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libxtst6 \
    xdg-utils \
    libatspi2.0-0 \
    libdrm2 \
    libgbm1 \
    libsecret-1-0 \
    2>/dev/null || true
}

install_via_apt() {
  log_step "Метод 1: Установка через APT-репозиторий"

  log_info "Добавляем GPG-ключ..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL "${APT_REPO_KEY_URL}" \
    | gpg --dearmor -o /etc/apt/keyrings/claude-desktop.gpg 2>/dev/null \
    || curl -fsSL "${APT_REPO_KEY_URL}" \
       | tee /etc/apt/keyrings/claude-desktop-raw.asc > /dev/null

  log_info "Добавляем репозиторий..."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/claude-desktop.gpg] \
${APT_REPO_URL} stable main" \
    | tee /etc/apt/sources.list.d/claude-desktop.list > /dev/null

  apt-get update -qq
  if apt-get install -y claude-desktop 2>/dev/null; then
    log_success "Claude Desktop установлен через APT!"
    return 0
  fi

  log_warn "APT-установка не удалась, пробуем через .deb..."
  return 1
}

install_via_deb() {
  log_step "Метод 2: Установка последнего .deb из GitHub Releases"

  log_info "Определяем последнюю версию..."
  local latest_url
  latest_url=$(curl -fsSL "https://api.github.com/repos/aaddrick/claude-desktop-debian/releases/latest" \
    | grep '"browser_download_url"' \
    | grep '\.deb"' \
    | grep "$(dpkg --print-architecture)" \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')

  if [ -z "${latest_url}" ]; then
    # Fallback — ищем без arch-фильтра
    latest_url=$(curl -fsSL "https://api.github.com/repos/aaddrick/claude-desktop-debian/releases/latest" \
      | grep '"browser_download_url"' \
      | grep '\.deb"' \
      | head -1 \
      | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')
  fi

  if [ -z "${latest_url}" ]; then
    log_error "Не удалось определить URL для скачивания .deb"
    exit 1
  fi

  local deb_file="/tmp/claude-desktop.deb"
  log_info "Скачиваем: ${latest_url}"
  curl -fsSL -o "${deb_file}" "${latest_url}"

  log_info "Устанавливаем пакет..."
  dpkg -i "${deb_file}" || apt-get install -f -y -qq
  rm -f "${deb_file}"

  log_success "Claude Desktop установлен!"
}

verify_install() {
  if command -v claude-desktop &>/dev/null || [ -f "/usr/bin/claude-desktop" ] || [ -f "/usr/local/bin/claude-desktop" ]; then
    log_success "Claude Desktop успешно установлен."
    log_info "Запуск: claude-desktop (или через меню приложений)"
    log_info "Поддержка MCP: ~/.config/claude-desktop/"
  else
    log_warn "Бинарник claude-desktop не найден в PATH."
    log_info "Проверьте: dpkg -l | grep claude"
  fi
}

check_distro
install_dependencies

# Пробуем APT сначала, потом .deb
if ! install_via_apt 2>/dev/null; then
  install_via_deb
fi

verify_install
