#!/usr/bin/env bash
# =============================================================================
# ProxyBridge Installer
# https://github.com/InterceptSuite/ProxyBridge
#
# Использует официальный deploy.sh от InterceptSuite.
# Скрипт предполагает запуск от root (проверка производится в родительском install.sh).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs"

# --- Проверка версии glibc ---
# ProxyBridge v3.2.0 (первый стабильный Linux-релиз) требует glibc >= 2.38
# Debian 12 (Bookworm) поставляется с glibc 2.36 — бинарник не запустится.
REQUIRED_GLIBC="2.38"
CURRENT_GLIBC=$(ldd --version 2>/dev/null | awk 'NR==1{print $NF}' || echo "0")

version_ge() {
  # Возвращает 0 (true) если $1 >= $2
  printf '%s\n%s' "$2" "$1" | sort -C -V
}

if ! version_ge "$CURRENT_GLIBC" "$REQUIRED_GLIBC"; then
  echo -e "${YELLOW:-$'\033[1;33m'}[WARN]${NC:-$'\033[0m'} ProxyBridge требует glibc >= ${REQUIRED_GLIBC}, обнаружена ${CURRENT_GLIBC}."
  echo -e "${YELLOW:-$'\033[1;33m'}[WARN]${NC:-$'\033[0m'} Debian 12 (Bookworm) несовместим. Требуется Debian 13+ или Ubuntu 23.10+."
  echo -e "${YELLOW:-$'\033[1;33m'}[WARN]${NC:-$'\033[0m'} Установка ProxyBridge пропущена."
  exit 0
fi

PROXYBRIDGE_DEPLOY_URL="https://raw.githubusercontent.com/InterceptSuite/ProxyBridge/refs/heads/master/Linux/deploy.sh"
DEPLOY_SCRIPT="/tmp/proxybridge-deploy-$$.sh"

# --- Цвета (если не переданы из родительского) ---
GREEN="${GREEN:-$'\033[0;32m'}"
YELLOW="${YELLOW:-$'\033[1;33m'}"
RED="${RED:-$'\033[0;31m'}"
BOLD="${BOLD:-$'\033[1m'}"
NC="${NC:-$'\033[0m'}"

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# --- Проверка зависимостей для скачивания ---
if ! command -v curl &>/dev/null; then
  log_info "Устанавливаю curl..."
  apt-get update -qq
  apt-get install -y -qq curl
fi

# --- Скачать официальный deploy.sh ---
log_info "Скачиваю официальный ProxyBridge deploy.sh..."
if ! curl -fsSL -o "${DEPLOY_SCRIPT}" "${PROXYBRIDGE_DEPLOY_URL}"; then
  log_error "Не удалось скачать deploy.sh с ${PROXYBRIDGE_DEPLOY_URL}"
  exit 1
fi
chmod +x "${DEPLOY_SCRIPT}"
log_success "deploy.sh скачан"

# --- Запускаем официальный установщик (мы уже root, sudo не нужен) ---
log_info "Запускаю официальный ProxyBridge установщик..."
bash "${DEPLOY_SCRIPT}"
DEPLOY_EXIT=$?

# --- Очистка ---
rm -f "${DEPLOY_SCRIPT}"

if [ "${DEPLOY_EXIT}" -ne 0 ]; then
  log_error "ProxyBridge установщик завершился с ошибкой (exit ${DEPLOY_EXIT})"
  exit "${DEPLOY_EXIT}"
fi

# deploy.sh оставляет активные nftables NFQUEUE-правила после установки.
# Без запущенного демона ProxyBridge весь исходящий трафик зависает в очереди.
# Выполняем --cleanup чтобы снять правила немедленно после установки.
log_info "Очистка nftables-правил ProxyBridge после установки..."
/usr/local/bin/ProxyBridge --cleanup 2>/dev/null || true
log_success "nftables очищены"

log_success "ProxyBridge успешно установлен"

# --- Копируем конфиг из репозитория ---
CONFIG_SRC="${CONFIGS_DIR}/proxybridge/config"
if [ ! -f "${CONFIG_SRC}" ]; then
  log_error "Не найден конфиг: ${CONFIG_SRC}"
  exit 1
fi
log_info "Копирую конфигурацию (direct-режим)..."
mkdir -p /etc/proxybridge
# Не перезаписываем если уже существует (пользователь мог изменить)
if [ ! -f /etc/proxybridge/config ]; then
  cp "${CONFIG_SRC}" /etc/proxybridge/config
  log_success "Конфиг установлен: /etc/proxybridge/config"
else
  log_info "Конфиг уже существует, пропускаю: /etc/proxybridge/config"
fi

# --- Копируем systemd-сервис из репозитория ---
SERVICE_SRC="${CONFIGS_DIR}/systemd/proxybridge.service"
if [ ! -f "${SERVICE_SRC}" ]; then
  log_error "Не найден systemd-юнит: ${SERVICE_SRC}"
  exit 1
fi
log_info "Устанавливаю systemd-сервис proxybridge..."
cp "${SERVICE_SRC}" /etc/systemd/system/proxybridge.service
log_success "Сервис установлен: /etc/systemd/system/proxybridge.service"

# --- Активируем сервис ---
log_info "Активирую и запускаю proxybridge..."
systemctl daemon-reload
systemctl enable proxybridge
systemctl start proxybridge
sleep 1
if systemctl is-active --quiet proxybridge; then
  log_success "proxybridge запущен (direct-режим — весь трафик напрямую)"
else
  log_warn "proxybridge не запустился, проверь: journalctl -u proxybridge -n 20"
fi

log_info ""
log_info "╔══════════════════════════════════════════════════════╗"
log_info "║  ProxyBridge работает в режиме DIRECT (без прокси)  ║"
log_info "║  Весь трафик пропускается напрямую.                 ║"
log_info "╚══════════════════════════════════════════════════════╝"
log_info ""
log_info "Чтобы включить прокси, отредактируй /etc/proxybridge/config:"
log_info "  1. Замени 'RULE=*:*:*:BOTH:DIRECT' на 'RULE=*:*:*:BOTH:PROXY'"
log_info "  2. Добавь строку 'PROXY=socks5://127.0.0.1:1080'"
log_info "  3. Перезапусти: systemctl restart proxybridge"
log_info ""
log_info "Полезные команды:"
log_info "  systemctl status proxybridge"
log_info "  systemctl restart proxybridge"
log_info "  journalctl -u proxybridge -f"
log_info "  ProxyBridge --help"
log_info "  ProxyBridge --cleanup   (очистка nftables после сбоя)"
if [ -f /usr/local/bin/ProxyBridgeGUI ]; then
  log_info "  ProxyBridgeGUI          (графический интерфейс, требует GTK3)"
fi
