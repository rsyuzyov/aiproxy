#!/usr/bin/env bash
# =============================================================================
# Настройка подключения AmneziaWG из .conf-файла
#
# Использование:
#   setup-amnezia-connection.sh <путь_к_conf> [имя_интерфейса]
#
# Примеры:
#   setup-amnezia-connection.sh /root/amnezia.conf
#   setup-amnezia-connection.sh /root/amnezia.conf office-vpn
#
# Аргументы:
#   <путь_к_conf>      — путь к конфигурационному файлу AmneziaWG (обязательно)
#   [имя_интерфейса]   — имя WG-интерфейса (по умолчанию: amnezia0)
#
# Управление туннелем после настройки:
#   systemctl start  awg-quick@<имя>   — включить
#   systemctl stop   awg-quick@<имя>   — выключить
#   systemctl status awg-quick@<имя>   — статус
#   awg show                            — показать активные туннели
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[amnezia-conn]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[amnezia-conn]${NC} $*"; }
log_error()   { echo -e "${RED}[amnezia-conn]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[amnezia-conn] OK:${NC} $*"; }

CONF_DIR="/etc/amnezia/amneziawg"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

show_usage() {
  cat <<EOF
${BOLD}Использование:${NC}
  $0 <путь_к_conf> [имя_интерфейса]

${BOLD}Аргументы:${NC}
  <путь_к_conf>      Путь к .conf-файлу AmneziaWG (формат WireGuard + поля Jc/Jmin/H1-H4)
  [имя_интерфейса]   Имя интерфейса (по умолчанию: amnezia0)

${BOLD}Примеры:${NC}
  $0 /root/amnezia.conf
  $0 /root/amnezia.conf office-vpn

${BOLD}Управление туннелем:${NC}
  systemctl start   awg-quick@amnezia0
  systemctl stop    awg-quick@amnezia0
  systemctl status  awg-quick@amnezia0
  awg show
EOF
}

validate_conf_file() {
  local conf_file="$1"

  if [ ! -f "${conf_file}" ]; then
    log_error "Файл не найден: ${conf_file}"
    exit 1
  fi

  if [ ! -r "${conf_file}" ]; then
    log_error "Нет прав на чтение файла: ${conf_file}"
    exit 1
  fi

  # Проверяем что это WireGuard/AmneziaWG формат
  if ! grep -q '^\[Interface\]' "${conf_file}"; then
    log_error "Файл не является корректным WireGuard/AmneziaWG конфигом (отсутствует секция [Interface])"
    log_error "Убедитесь что используете .conf-файл, экспортированный из Amnezia (не .vpn)"
    exit 1
  fi

  if ! grep -q '^\[Peer\]' "${conf_file}"; then
    log_warn "Секция [Peer] не найдена — конфиг может быть неполным"
  fi

  log_success "Файл конфигурации корректен"
}

check_amneziawg_installed() {
  if ! command -v awg-quick &>/dev/null && ! command -v wg-quick &>/dev/null; then
    log_error "awg-quick / wg-quick не найдены. Сначала установите AmneziaWG:"
    log_error "  bash ${HOME}/aiproxy/scripts/install-amnezia.sh"
    exit 1
  fi

  # Определяем какой инструмент доступен
  if command -v awg-quick &>/dev/null; then
    echo "awg-quick"
  else
    log_warn "awg-quick не найден, используется wg-quick (обфускация может не работать)"
    echo "wg-quick"
  fi
}

stop_existing_tunnel() {
  local iface="$1"
  local quick_cmd="$2"

  if systemctl is-active --quiet "awg-quick@${iface}" 2>/dev/null || \
     systemctl is-active --quiet "wg-quick@${iface}" 2>/dev/null; then
    log_info "Останавливаю существующий туннель ${iface}..."
    systemctl stop "awg-quick@${iface}" 2>/dev/null || \
    systemctl stop "wg-quick@${iface}"  2>/dev/null || true
  fi

  # Принудительно снять интерфейс если он поднят
  if ip link show "${iface}" &>/dev/null 2>&1; then
    log_info "Снимаю интерфейс ${iface}..."
    "${quick_cmd}" down "${CONF_DIR}/${iface}.conf" 2>/dev/null || true
  fi
}

install_config() {
  local src_conf="$1"
  local iface="$2"
  local dest_conf="${CONF_DIR}/${iface}.conf"

  mkdir -p "${CONF_DIR}"
  chmod 700 "${CONF_DIR}"

  log_info "Копирую конфиг в ${dest_conf}..."
  cp "${src_conf}" "${dest_conf}"
  chmod 600 "${dest_conf}"
  log_success "Конфиг установлен: ${dest_conf}"
}

enable_systemd_service() {
  local iface="$1"
  local quick_cmd="$2"

  # Определяем имя service-unit
  local unit_name
  if [ "${quick_cmd}" = "awg-quick" ]; then
    unit_name="awg-quick@${iface}"
  else
    unit_name="wg-quick@${iface}"
  fi

  log_info "Включаю автозапуск службы ${unit_name}..."
  systemctl enable "${unit_name}"

  log_info "Запускаю туннель ${iface}..."
  systemctl start "${unit_name}"

  # Проверяем статус
  sleep 1
  if systemctl is-active --quiet "${unit_name}"; then
    log_success "Туннель ${iface} активен"
  else
    log_warn "Служба ${unit_name} не запустилась. Проверьте:"
    log_warn "  journalctl -u ${unit_name} -n 30"
    log_warn "  systemctl status ${unit_name}"
    exit 1
  fi
}

show_connection_info() {
  local iface="$1"
  local conf_file="$2"

  echo ""
  echo -e "${BOLD}${GREEN}Подключение настроено!${NC}"
  echo ""

  # Показать адрес интерфейса из конфига
  local addr
  addr="$(grep -E '^Address\s*=' "${conf_file}" | head -1 | sed 's/^Address\s*=\s*//' || echo 'не указан')"
  log_info "Адрес интерфейса: ${addr}"

  # Показать endpoint из конфига
  local endpoint
  endpoint="$(grep -E '^Endpoint\s*=' "${conf_file}" | head -1 | sed 's/^Endpoint\s*=\s*//' || echo 'не указан')"
  log_info "Сервер (Endpoint): ${endpoint}"

  # Показать DNS
  local dns
  dns="$(grep -E '^DNS\s*=' "${conf_file}" | head -1 | sed 's/^DNS\s*=\s*//' || echo 'не задан')"
  log_info "DNS: ${dns}"

  cat <<EOF

${BOLD}Управление туннелем:${NC}
  systemctl start   awg-quick@${iface}  — включить VPN
  systemctl stop    awg-quick@${iface}  — выключить VPN
  systemctl status  awg-quick@${iface}  — статус
  awg show                               — показать активные туннели и трафик

${BOLD}Конфиг:${NC}
  ${CONF_DIR}/${iface}.conf
EOF
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  # Проверка аргументов
  if [ "$#" -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    [ "$#" -lt 1 ] && exit 1 || exit 0
  fi

  local conf_file="$1"
  local iface="${2:-amnezia0}"

  # Валидация имени интерфейса (только буквы, цифры, дефис; макс 15 символов)
  if ! echo "${iface}" | grep -qE '^[a-zA-Z0-9-]{1,15}$'; then
    log_error "Некорректное имя интерфейса: '${iface}' (допустимы буквы, цифры, дефис; макс 15 символов)"
    exit 1
  fi

  log_info "Конфиг:    ${conf_file}"
  log_info "Интерфейс: ${iface}"

  validate_conf_file "${conf_file}"

  local quick_cmd
  quick_cmd="$(check_amneziawg_installed)"

  stop_existing_tunnel "${iface}" "${quick_cmd}"
  install_config "${conf_file}" "${iface}"
  enable_systemd_service "${iface}" "${quick_cmd}"
  show_connection_info "${iface}" "${CONF_DIR}/${iface}.conf"
}

main "$@"
