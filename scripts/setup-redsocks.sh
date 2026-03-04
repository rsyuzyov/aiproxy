#!/usr/bin/env bash
# =============================================================================
# Настройка redsocks: установка адреса прокси, логина и пароля
# Использование:
#   setup-redsocks.sh <proxy_ip> <proxy_port> <login> <password> [local_port]
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[redsocks]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[redsocks]${NC} $*"; }
log_error()   { echo -e "${RED}[redsocks]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[redsocks] OK:${NC} $*"; }

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_TOGGLE="${SCRIPTS_DIR}/proxy-toggle.sh"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

prepare_noninteractive_apt() {
  export DEBIAN_FRONTEND=noninteractive

  # Убрать интерактивные вопросы iptables-persistent в контейнерах/CI
  if command -v debconf-set-selections &>/dev/null; then
    echo 'iptables-persistent iptables-persistent/autosave_v4 boolean false' | debconf-set-selections || true
    echo 'iptables-persistent iptables-persistent/autosave_v6 boolean false' | debconf-set-selections || true
  fi
}

install_redsocks() {
  if command -v redsocks &>/dev/null; then
    return
  fi

  prepare_noninteractive_apt

  log_info "Устанавливаю redsocks..."
  apt-get update -qq
  apt-get install -y -qq redsocks iptables netfilter-persistent iptables-persistent
  log_success "redsocks установлен"
}

ensure_local_scripts_executable() {
  log_info "Проверяю локальные скрипты в каталоге репозитория..."

  chmod +x "${PROXY_TOGGLE}"
  chmod +x "${SCRIPTS_DIR}/setup-redsocks.sh"

  log_success "Локальные скрипты готовы к запуску из ${SCRIPTS_DIR}"
}

validate_args() {
  local ip="$1" port="$2" local_port="$3"

  if [[ ! "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Неверный IP-адрес прокси: ${ip}"
    exit 1
  fi

  if [[ ! "${port}" =~ ^[0-9]+$ ]] || [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
    log_error "Неверный порт прокси: ${port}"
    exit 1
  fi

  if [[ ! "${local_port}" =~ ^[0-9]+$ ]] || [ "${local_port}" -lt 1 ] || [ "${local_port}" -gt 65535 ]; then
    log_error "Неверный локальный порт: ${local_port}"
    exit 1
  fi
}

write_redsocks_conf() {
  local ip="$1" port="$2" login="$3" password="$4" local_port="$5"

  log_info "Записываю /etc/redsocks.conf..."

  cat > /etc/redsocks.conf <<EOF
base {
  log_debug = off;
  log_info = on;
  daemon = on;
  redirector = iptables;
}

redsocks {
  local_ip = 127.0.0.1;
  local_port = ${local_port};
  ip = ${ip};
  port = ${port};
  type = socks5;
  login = "${login}";
  password = "${password}";
}
EOF

  chmod 600 /etc/redsocks.conf
  log_success "Конфигурация redsocks записана"
}

setup_iptables() {
  local ip="$1" local_port="$2"

  log_info "Настраиваю iptables правила..."

  # Создать цепочку REDSOCKS если не существует
  iptables -t nat -N REDSOCKS 2>/dev/null || true
  # Очистить цепочку
  iptables -t nat -F REDSOCKS

  # Исключить private/local сети из редиректа
  local bypass_nets=(
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "224.0.0.0/4"
    "240.0.0.0/4"
  )

  for net in "${bypass_nets[@]}"; do
    iptables -t nat -A REDSOCKS -d "${net}" -j RETURN
  done

  # Исключить сам прокси-сервер (чтобы не зациклиться)
  iptables -t nat -A REDSOCKS -d "${ip}/32" -j RETURN

  # Весь остальной TCP → redsocks
  iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports "${local_port}"

  # Убрать дублирующие правила OUTPUT
  while iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null; do
    iptables -t nat -D OUTPUT -p tcp -j REDSOCKS
  done

  # Добавить правило OUTPUT
  iptables -t nat -A OUTPUT -p tcp -j REDSOCKS

  # Сохранить правила
  if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save >/dev/null
  elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
  fi

  log_success "iptables настроен"
}

prepare_redsocks_service() {
  # Проверить конфиг
  redsocks -t -c /etc/redsocks.conf || { log_error "Ошибка в конфигурации redsocks"; exit 1; }

  # Включаем unit, но старт/стоп делаем через proxy-toggle.sh
  systemctl enable redsocks >/dev/null 2>&1 || true
  log_success "Служба redsocks подготовлена"
}

set_initial_bypass_mode() {
  log_info "Применяю начальный режим прокси: OFF (как ${PROXY_TOGGLE} off)..."
  "${PROXY_TOGGLE}" off
}

show_usage() {
  cat <<EOF
Использование: $0 <proxy_ip> <proxy_port> <login> <password> [local_port]

Аргументы:
  proxy_ip     IP-адрес SOCKS5 прокси-сервера
  proxy_port   Порт прокси-сервера
  login        Логин для аутентификации
  password     Пароль для аутентификации
  local_port   Локальный порт redsocks (по умолчанию: 12345)

Примеры:
  $0 1.2.3.4 1080 myuser mypassword
  $0 1.2.3.4 1080 myuser mypassword 12345

После настройки управляйте прокси через локальный скрипт:
  ${PROXY_TOGGLE} on|off|status
EOF
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
    show_usage
    exit 1
  fi

  local PROXY_IP="$1"
  local PROXY_PORT="$2"
  local PROXY_LOGIN="$3"
  local PROXY_PASSWORD="$4"
  local LOCAL_PORT="${5:-12345}"

  validate_args "${PROXY_IP}" "${PROXY_PORT}" "${LOCAL_PORT}"

  install_redsocks
  ensure_local_scripts_executable
  write_redsocks_conf "${PROXY_IP}" "${PROXY_PORT}" "${PROXY_LOGIN}" "${PROXY_PASSWORD}" "${LOCAL_PORT}"
  prepare_redsocks_service
  setup_iptables "${PROXY_IP}" "${LOCAL_PORT}"
  set_initial_bypass_mode

  echo ""
  log_success "redsocks настроен: ${PROXY_IP}:${PROXY_PORT}"
  log_info "Управление прокси:"
  log_info "  ${PROXY_TOGGLE} on     — включить"
  log_info "  ${PROXY_TOGGLE} off    — выключить"
  log_info "  ${PROXY_TOGGLE} status — статус"
  log_info ""
  log_info "Обновить настройки прокси:"
  log_info "  ${SCRIPTS_DIR}/setup-redsocks.sh <ip> <port> <login> <pass>"
}

main "$@"
