#!/usr/bin/env bash
# =============================================================================
# ProxyBridge Installer
# https://github.com/InterceptSuite/ProxyBridge
#
# Использует официальный deploy.sh от InterceptSuite.
# Скрипт предполагает запуск от root (проверка производится в родительском install.sh).
# =============================================================================
set -euo pipefail

PROXYBRIDGE_DEPLOY_URL="https://raw.githubusercontent.com/InterceptSuite/ProxyBridge/refs/heads/master/Linux/deploy.sh"
DEPLOY_SCRIPT="/tmp/proxybridge-deploy-$$.sh"

# --- Цвета (если не переданы из родительского) ---
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
RED="${RED:-\033[0;31m}"
BOLD="${BOLD:-\033[1m}"
NC="${NC:-\033[0m}"

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

log_success "ProxyBridge успешно установлен"
log_info "Команды:"
log_info "  ProxyBridge --help"
log_info "  ProxyBridge --proxy socks5://IP:PORT --rule \"app:*:*:TCP:PROXY\""
log_info "  ProxyBridge --cleanup   (очистка после сбоя)"
if [ -f /usr/local/bin/ProxyBridgeGUI ]; then
  log_info "  ProxyBridgeGUI          (графический интерфейс, требует GTK3)"
fi
