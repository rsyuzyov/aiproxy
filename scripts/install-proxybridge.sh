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
  apt-get install -y curl
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
DEPLOY_EXIT=0
bash "${DEPLOY_SCRIPT}" || DEPLOY_EXIT=$?

# --- Очистка ---
rm -f "${DEPLOY_SCRIPT}"

if [ "${DEPLOY_EXIT}" -ne 0 ]; then
  log_warn "ProxyBridge deploy.sh завершился с кодом ${DEPLOY_EXIT}"
  if [ ! -x /usr/local/bin/ProxyBridge ]; then
    log_error "Бинарник ProxyBridge не найден — установка не удалась"
    exit "${DEPLOY_EXIT}"
  fi
  log_info "Бинарник ProxyBridge на месте, продолжаю настройку..."
fi

# deploy.sh оставляет активные nftables NFQUEUE-правила после установки.
# Без запущенного демона ProxyBridge весь исходящий трафик зависает в очереди.
# Выполняем --cleanup чтобы снять правила немедленно после установки.
log_info "Очистка nftables-правил ProxyBridge после установки..."
/usr/local/bin/ProxyBridge --cleanup 2>/dev/null || true
log_success "nftables очищены"

log_success "ProxyBridge успешно установлен"

# --- Копируем конфиг из репозитория ---
CONFIG_SRC="${CONFIGS_DIR}/proxybridge/config.ini"
if [ ! -f "${CONFIG_SRC}" ]; then
  log_error "Не найден конфиг: ${CONFIG_SRC}"
  exit 1
fi
log_info "Копирую конфигурацию (direct-режим)..."
mkdir -p /etc/proxybridge
# Не перезаписываем если уже существует (пользователь или GUI мог изменить)
if [ ! -f /etc/proxybridge/config.ini ]; then
  sed 's/\r$//' "${CONFIG_SRC}" > /etc/proxybridge/config.ini
  log_success "Конфиг установлен: /etc/proxybridge/config.ini"
else
  log_info "Конфиг уже существует, пропускаю: /etc/proxybridge/config.ini"
fi

# --- Копируем скрипт генерации аргументов ---
GENARGS_SRC="${SCRIPT_DIR}/proxybridge-gen-args.sh"
if [ -f "${GENARGS_SRC}" ]; then
  mkdir -p /usr/local/lib/proxybridge
  sed 's/\r$//' "${GENARGS_SRC}" > /usr/local/lib/proxybridge/gen-args.sh
  chmod +x /usr/local/lib/proxybridge/gen-args.sh
  log_success "Скрипт gen-args.sh установлен"
fi

# --- Копируем GUI-обёртку и ярлык (если ProxyBridgeGUI установлен) ---
if [ -x /usr/local/bin/ProxyBridgeGUI ]; then
  GUIWRAP_SRC="${SCRIPT_DIR}/proxybridge-gui-wrapper.sh"
  DESKTOP_SRC="${CONFIGS_DIR}/proxybridge/proxybridge-gui.desktop"

  if [ -f "${GUIWRAP_SRC}" ]; then
    mkdir -p /usr/local/lib/proxybridge
    sed 's/\r$//' "${GUIWRAP_SRC}" > /usr/local/lib/proxybridge/gui-wrapper.sh
    chmod +x /usr/local/lib/proxybridge/gui-wrapper.sh
    log_success "GUI-обёртка установлена"
  fi

  if [ -f "${DESKTOP_SRC}" ]; then
    mkdir -p /usr/share/applications
    sed 's/\r$//' "${DESKTOP_SRC}" > /usr/share/applications/proxybridge-gui.desktop
    log_success "Ярлык добавлен в меню: Proxy Bridge"
  fi
fi

# --- Копируем systemd-сервис из репозитория ---
SERVICE_SRC="${CONFIGS_DIR}/systemd/proxybridge.service"
if [ ! -f "${SERVICE_SRC}" ]; then
  log_error "Не найден systemd-юнит: ${SERVICE_SRC}"
  exit 1
fi
log_info "Устанавливаю systemd-сервис proxybridge..."
sed 's/\r$//' "${SERVICE_SRC}" > /etc/systemd/system/proxybridge.service
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
log_info "Чтобы включить прокси:"
log_info "  Вариант 1: sudo ProxyBridgeGUI (если установлен)"
log_info "  Вариант 2: отредактируй /etc/proxybridge/config.ini"
log_info "    В [RULES] замени action 1 (DIRECT) на 0 (PROXY)"
log_info "    В [SETTINGS] укажи ip и port прокси-сервера"
log_info "    Перезапусти: systemctl restart proxybridge"
log_info ""
log_info "Конфиг: /etc/proxybridge/config.ini (единый для GUI и systemd)"
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
