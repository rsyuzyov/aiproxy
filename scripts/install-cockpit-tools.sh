#!/usr/bin/env bash
# =============================================================================
# Установка Cockpit Tools
# https://github.com/jlcodes99/cockpit-tools
# Универсальный менеджер аккаунтов для AI IDE:
# Antigravity, Codex, GitHub Copilot, Windsurf, Kiro, Cursor
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

GITHUB_REPO="jlcodes99/cockpit-tools"
INSTALL_USER="${SUDO_USER:-${USER:-root}}"

check_distro() {
  if ! command -v apt-get &>/dev/null; then
    log_error "Этот скрипт предназначен для Debian/Ubuntu (apt-based систем)."
    exit 1
  fi
}

get_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64)  echo "x86_64" ;;
    aarch64) echo "arm64" ;;
    armv7l)  echo "armv7l" ;;
    *)       echo "${arch}" ;;
  esac
}

install_cockpit_tools() {
  log_step "Установка Cockpit Tools"

  export DEBIAN_FRONTEND=noninteractive

  log_info "Устанавливаем зависимости..."
  apt-get update -qq
  apt-get install -y -qq curl jq libgtk-3-0 libnotify4 libnss3 libxss1 xdg-utils \
    libatspi2.0-0 libdrm2 libgbm1 libsecret-1-0 2>/dev/null || true

  log_info "Определяем последнюю версию Cockpit Tools..."

  local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
  local release_info
  release_info=$(curl -fsSL "${api_url}")

  local version
  version=$(echo "${release_info}" | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/' | head -1)
  log_info "Последняя версия: ${version}"

  # Ищем .deb для нашей архитектуры
  local arch
  arch="$(get_arch)"
  local deb_url

  # Пробуем amd64 (основная архитектура)
  deb_url=$(echo "${release_info}" \
    | grep '"browser_download_url"' \
    | grep '\.deb"' \
    | grep -i "amd64\|x86_64\|linux" \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')

  # Если не нашли — берём любой .deb
  if [ -z "${deb_url}" ]; then
    deb_url=$(echo "${release_info}" \
      | grep '"browser_download_url"' \
      | grep '\.deb"' \
      | head -1 \
      | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')
  fi

  # Если .deb не нашли — берём .AppImage
  local appimage_url=""
  if [ -z "${deb_url}" ]; then
    log_warn ".deb не найден, ищем .AppImage..."
    appimage_url=$(echo "${release_info}" \
      | grep '"browser_download_url"' \
      | grep '\.AppImage"' \
      | head -1 \
      | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')
  fi

  if [ -n "${deb_url}" ]; then
    # Установка через .deb
    local deb_file="/tmp/cockpit-tools.deb"
    log_info "Скачиваем .deb: ${deb_url}"
    curl -fsSL -o "${deb_file}" "${deb_url}"

    log_info "Устанавливаем пакет..."
    dpkg -i "${deb_file}" || apt-get install -f -y -qq
    rm -f "${deb_file}"

    log_success "Cockpit Tools ${version} установлен!"
    log_info "Запуск: cockpit-tools (или через меню приложений)"

  elif [ -n "${appimage_url}" ]; then
    # Fallback: установка .AppImage
    local appimage_dir="/opt/cockpit-tools"
    local appimage_bin="/usr/local/bin/cockpit-tools"

    mkdir -p "${appimage_dir}"

    log_info "Скачиваем .AppImage: ${appimage_url}"
    local appimage_name
    appimage_name=$(basename "${appimage_url}")
    curl -fsSL -o "${appimage_dir}/${appimage_name}" "${appimage_url}"
    chmod +x "${appimage_dir}/${appimage_name}"

    # Симлинк
    ln -sf "${appimage_dir}/${appimage_name}" "${appimage_bin}"

    # Desktop-ярлык
    cat > /usr/share/applications/cockpit-tools.desktop <<DESKEOF
[Desktop Entry]
Name=Cockpit Tools
Comment=AI IDE Account Manager (Antigravity, Copilot, Windsurf, Cursor...)
Exec=${appimage_bin} --no-sandbox %U
Terminal=false
Type=Application
Categories=Development;Utility;
DESKEOF

    log_success "Cockpit Tools ${version} установлен как AppImage!"
    log_info "Запуск: cockpit-tools (или через меню приложений)"
    log_info "Путь: ${appimage_bin}"

  else
    log_error "Не удалось найти пакет для установки в релизе ${version}."
    log_error "Скачайте вручную: https://github.com/${GITHUB_REPO}/releases"
    exit 1
  fi
}

check_distro
install_cockpit_tools
