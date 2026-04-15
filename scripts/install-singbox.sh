#!/usr/bin/env bash
# =============================================================================
# Установка sing-box
# https://sing-box.sagernet.org/
#
# Использует официальный Debian-репозиторий sagernet.
# Переменная окружения GATE_MODE=1 устанавливает конфиг шлюза
# (SOCKS5 :1080 + TUN inbound, outbound=direct).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs"

GREEN="${GREEN:-$'\033[0;32m'}"
YELLOW="${YELLOW:-$'\033[1;33m'}"
RED="${RED:-$'\033[0;31m'}"
NC="${NC:-$'\033[0m'}"

log_info()    { echo -e "${GREEN}[sing-box]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[sing-box]${NC} $*"; }
log_error()   { echo -e "${RED}[sing-box]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[sing-box] OK:${NC} $*"; }

GATE_MODE="${GATE_MODE:-0}"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_repo() {
  log_info "Добавляю репозиторий sagernet..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg

  mkdir -p /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/sagernet.asc ]; then
    curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
    chmod a+r /etc/apt/keyrings/sagernet.asc
  fi

  cat > /etc/apt/sources.list.d/sagernet.sources <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF

  apt-get update -qq
}

install_singbox() {
  log_info "Устанавливаю пакет sing-box..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y sing-box

  if ! command -v sing-box &>/dev/null; then
    log_error "sing-box не найден после установки"
    exit 1
  fi

  log_success "sing-box установлен: $(sing-box version 2>&1 | head -1)"
}

install_config() {
  local src
  if [ "${GATE_MODE}" = "1" ]; then
    src="${CONFIGS_DIR}/singbox/gate.json"
    log_info "Режим шлюза — применяю ${src}"
  else
    src="${CONFIGS_DIR}/singbox/config.json"
    log_info "Нейтральный режим — применяю ${src}"
  fi

  if [ ! -f "${src}" ]; then
    log_error "Не найден конфиг: ${src}"
    exit 1
  fi

  mkdir -p /etc/sing-box
  if [ -f /etc/sing-box/config.json ] && [ "${GATE_MODE}" != "1" ]; then
    log_info "Конфиг уже существует — пропускаю (не перезатираю)"
  else
    sed 's/\r$//' "${src}" > /etc/sing-box/config.json
    log_success "Конфиг установлен: /etc/sing-box/config.json"
  fi

  if ! sing-box check -c /etc/sing-box/config.json; then
    log_error "Проверка конфига не пройдена"
    exit 1
  fi
  log_success "Конфиг валиден"
}

enable_service() {
  log_info "Включаю службу sing-box..."
  systemctl daemon-reload
  systemctl enable sing-box.service >/dev/null 2>&1 || true
  systemctl restart sing-box.service

  sleep 1
  if systemctl is-active --quiet sing-box.service; then
    log_success "sing-box запущен"
  else
    log_error "sing-box не запустился"
    systemctl status sing-box.service --no-pager || true
    exit 1
  fi
}

main() {
  require_root
  install_repo
  install_singbox
  install_config
  enable_service

  echo ""
  log_success "Установка sing-box завершена"
  if [ "${GATE_MODE}" = "1" ]; then
    echo "  SOCKS5:      0.0.0.0:1080"
    echo "  TUN-шлюз:    sing-tun (auto_route), укажи IP этого хоста как шлюз на клиенте"
    echo "  Outbound:    direct (через системный default gateway)"
  else
    echo "  SOCKS5:      0.0.0.0:1080 (direct outbound)"
  fi
  echo "  Конфиг:      /etc/sing-box/config.json"
  echo "  Логи:        journalctl -u sing-box -f"
}

main "$@"
