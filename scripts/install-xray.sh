#!/usr/bin/env bash
# =============================================================================
# Установка Xray-core
# https://github.com/XTLS/Xray-core
#
# Ставит бинарник из официального github release (без bash <(curl)).
# Переменная окружения GATE_MODE=1 устанавливает конфиг шлюза (SOCKS5 :8080).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs"

GREEN="${GREEN:-$'\033[0;32m'}"
YELLOW="${YELLOW:-$'\033[1;33m'}"
RED="${RED:-$'\033[0;31m'}"
NC="${NC:-$'\033[0m'}"

log_info()    { echo -e "${GREEN}[xray]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[xray]${NC} $*"; }
log_error()   { echo -e "${RED}[xray]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[xray] OK:${NC} $*"; }

GATE_MODE="${GATE_MODE:-0}"

XRAY_BIN=/usr/local/bin/xray
XRAY_CFG_DIR=/usr/local/etc/xray
XRAY_CFG="${XRAY_CFG_DIR}/config.json"

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
    x86_64|amd64)  echo "Xray-linux-64.zip" ;;
    aarch64|arm64) echo "Xray-linux-arm64-v8a.zip" ;;
    armv7l)        echo "Xray-linux-arm32-v7a.zip" ;;
    *) log_error "Неподдерживаемая архитектура: ${arch}"; exit 1 ;;
  esac
}

install_xray_binary() {
  apt-get update -qq
  apt-get install -y -qq curl unzip ca-certificates jq

  local asset tmp_zip tmp_dir version url
  asset="$(detect_asset)"
  tmp_dir="$(mktemp -d)"
  tmp_zip="${tmp_dir}/xray.zip"

  log_info "Узнаю последнюю версию Xray-core..."
  version="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)"
  if [ -z "${version}" ] || [ "${version}" = "null" ]; then
    log_error "Не удалось определить версию Xray"
    rm -rf "${tmp_dir}"
    exit 1
  fi
  log_info "Версия: ${version}, архив: ${asset}"

  url="https://github.com/XTLS/Xray-core/releases/download/${version}/${asset}"
  if ! curl -fsSL -o "${tmp_zip}" "${url}"; then
    log_error "Не удалось скачать ${url}"
    rm -rf "${tmp_dir}"
    exit 1
  fi

  unzip -oq "${tmp_zip}" -d "${tmp_dir}"
  install -m 0755 "${tmp_dir}/xray" "${XRAY_BIN}"
  mkdir -p "${XRAY_CFG_DIR}"
  mkdir -p /usr/local/share/xray
  [ -f "${tmp_dir}/geoip.dat" ]   && install -m 0644 "${tmp_dir}/geoip.dat"   /usr/local/share/xray/
  [ -f "${tmp_dir}/geosite.dat" ] && install -m 0644 "${tmp_dir}/geosite.dat" /usr/local/share/xray/

  rm -rf "${tmp_dir}"

  log_success "Xray установлен: $(${XRAY_BIN} version 2>&1 | head -1)"
}

install_config() {
  local src
  if [ "${GATE_MODE}" = "1" ]; then
    src="${CONFIGS_DIR}/xray/gate.json"
    log_info "Режим шлюза — применяю ${src}"
  else
    src="${CONFIGS_DIR}/xray/config.json"
    log_info "Нейтральный режим — применяю ${src}"
  fi

  if [ ! -f "${src}" ]; then
    log_error "Не найден конфиг: ${src}"
    exit 1
  fi

  mkdir -p "${XRAY_CFG_DIR}"
  if [ -f "${XRAY_CFG}" ] && [ "${GATE_MODE}" != "1" ]; then
    log_info "Конфиг уже существует — пропускаю (не перезатираю)"
  else
    sed 's/\r$//' "${src}" > "${XRAY_CFG}"
    log_success "Конфиг установлен: ${XRAY_CFG}"
  fi

  if ! "${XRAY_BIN}" -test -config "${XRAY_CFG}" >/dev/null 2>&1; then
    log_error "Проверка конфига не пройдена"
    "${XRAY_BIN}" -test -config "${XRAY_CFG}" || true
    exit 1
  fi
  log_success "Конфиг валиден"
}

install_service() {
  local unit_src="${CONFIGS_DIR}/systemd/xray.service"
  if [ ! -f "${unit_src}" ]; then
    log_error "Не найден unit: ${unit_src}"
    exit 1
  fi
  install -m 0644 "${unit_src}" /etc/systemd/system/xray.service
  systemctl daemon-reload
  systemctl enable xray.service >/dev/null 2>&1 || true
  systemctl restart xray.service

  sleep 1
  if systemctl is-active --quiet xray.service; then
    log_success "Xray запущен"
  else
    log_error "Xray не запустился"
    systemctl status xray.service --no-pager || true
    exit 1
  fi
}

main() {
  require_root
  install_xray_binary
  install_config
  install_service

  echo ""
  log_success "Установка Xray завершена"
  if [ "${GATE_MODE}" = "1" ]; then
    echo "  SOCKS5:      0.0.0.0:8080"
    echo "  Outbound:    direct (через системный default gateway)"
  else
    echo "  SOCKS5:      0.0.0.0:10808"
  fi
  echo "  Конфиг:      ${XRAY_CFG}"
  echo "  Логи:        journalctl -u xray -f"
}

main "$@"
