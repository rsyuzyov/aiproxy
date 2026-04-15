#!/usr/bin/env bash
# =============================================================================
# Установка 3x-ui (web-панель управления Xray)
# https://github.com/MHSanaei/3x-ui
#
# Ставит из официального github release tarball (без bash <(curl)).
# После установки дефолтные креды admin/admin, порт панели — см. x-ui settings.
# =============================================================================
set -euo pipefail

GREEN="${GREEN:-$'\033[0;32m'}"
YELLOW="${YELLOW:-$'\033[1;33m'}"
RED="${RED:-$'\033[0;31m'}"
NC="${NC:-$'\033[0m'}"

log_info()    { echo -e "${GREEN}[3x-ui]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[3x-ui]${NC} $*"; }
log_error()   { echo -e "${RED}[3x-ui]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[3x-ui] OK:${NC} $*"; }

INSTALL_DIR=/usr/local/x-ui

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

detect_asset() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64)  echo "x-ui-linux-amd64.tar.gz" ;;
    aarch64|arm64) echo "x-ui-linux-arm64.tar.gz" ;;
    armv7l)        echo "x-ui-linux-armv7.tar.gz" ;;
    *) log_error "Неподдерживаемая архитектура: ${arch}"; exit 1 ;;
  esac
}

install_deps() {
  apt-get update -qq
  apt-get install -y -qq curl tar ca-certificates jq
}

install_3xui() {
  systemctl stop x-ui.service 2>/dev/null || true

  local asset tmp_dir tmp_tar version url
  asset="$(detect_asset)"
  tmp_dir="$(mktemp -d)"
  tmp_tar="${tmp_dir}/${asset}"

  log_info "Узнаю последнюю версию 3x-ui..."
  version="$(curl -fsSL https://api.github.com/repos/MHSanaei/3x-ui/releases/latest | jq -r .tag_name)"
  if [ -z "${version}" ] || [ "${version}" = "null" ]; then
    log_error "Не удалось определить версию 3x-ui"
    rm -rf "${tmp_dir}"
    exit 1
  fi
  log_info "Версия: ${version}, архив: ${asset}"

  url="https://github.com/MHSanaei/3x-ui/releases/download/${version}/${asset}"
  if ! curl -fsSL -o "${tmp_tar}" "${url}"; then
    log_error "Не удалось скачать ${url}"
    rm -rf "${tmp_dir}"
    exit 1
  fi

  rm -rf "${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}"
  tar -xzf "${tmp_tar}" -C "${tmp_dir}"

  # Архив распаковывается в каталог x-ui/
  if [ ! -d "${tmp_dir}/x-ui" ]; then
    log_error "Неожиданная структура архива"
    rm -rf "${tmp_dir}"
    exit 1
  fi

  cp -r "${tmp_dir}/x-ui/." "${INSTALL_DIR}/"
  chmod +x "${INSTALL_DIR}/x-ui" "${INSTALL_DIR}/bin/xray-linux-"* 2>/dev/null || true

  # Утилита-обёртка в /usr/bin
  if [ -f "${INSTALL_DIR}/x-ui.sh" ]; then
    install -m 0755 "${INSTALL_DIR}/x-ui.sh" /usr/bin/x-ui
  fi

  # systemd unit идёт в архиве
  if [ -f "${INSTALL_DIR}/x-ui.service" ]; then
    install -m 0644 "${INSTALL_DIR}/x-ui.service" /etc/systemd/system/x-ui.service
  else
    log_error "В архиве нет x-ui.service"
    rm -rf "${tmp_dir}"
    exit 1
  fi

  rm -rf "${tmp_dir}"
  log_success "3x-ui распакован в ${INSTALL_DIR}"
}

enable_service() {
  systemctl daemon-reload
  systemctl enable x-ui.service >/dev/null 2>&1 || true
  systemctl restart x-ui.service

  sleep 2
  if systemctl is-active --quiet x-ui.service; then
    log_success "3x-ui запущен"
  else
    log_error "3x-ui не запустился"
    systemctl status x-ui.service --no-pager || true
    exit 1
  fi
}

main() {
  require_root
  install_deps
  install_3xui
  enable_service

  echo ""
  log_success "Установка 3x-ui завершена"
  echo "  Управление:  x-ui"
  echo "  Логи:        journalctl -u x-ui -f"
  echo ""
  log_warn "Дефолтные креды: admin/admin. Порт панели и логин смени сразу командой 'x-ui'."
}

main "$@"
