#!/usr/bin/env bash
# =============================================================================
# Установка службы OmniRoute (npm-пакет)
# https://github.com/diegosouzapw/OmniRoute
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[omniroute]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[omniroute]${NC} $*"; }
log_error()   { echo -e "${RED}[omniroute]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[omniroute] OK:${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_TEMPLATE="${SCRIPT_DIR}/../configs/systemd/omniroute.service"
DESKTOP_DIR="${SCRIPT_DIR}/../configs/desktop"
SERVICE_NAME="omniroute"
NODE_VERSION="24"  # OmniRoute engines: >=20.20.2 <21 || >=22.22.2 <23 || >=24.0.0 <25

# --- Параметры службы ---
ENV_DIR="/etc/omniroute"
ENV_FILE="${ENV_DIR}/omniroute.env"
DATA_DIR="/var/lib/omniroute"
OMNIROUTE_PORT="20129"      # дашборд + API (9router занимает дефолтный 20128)
OMNIROUTE_WS_PORT="20130"   # live-WebSocket (дефолт 20129 пересекается с PORT выше)
OMNIROUTE_HOST="0.0.0.0"    # доступ из LAN

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_deps() {
  local pkgs=()
  command -v openssl &>/dev/null || pkgs+=(openssl)
  command -v curl    &>/dev/null || pkgs+=(curl)
  if [ "${#pkgs[@]}" -gt 0 ]; then
    log_info "Устанавливаю зависимости: ${pkgs[*]}"
    apt-get update -qq
    apt-get install -y "${pkgs[@]}"
  fi
}

install_nodejs() {
  if command -v node &>/dev/null; then
    local ver
    ver="$(node --version | tr -d 'v' | cut -d. -f1)"
    if [ "${ver}" -ge "${NODE_VERSION}" ]; then
      log_info "Node.js уже установлен: $(node --version)"
      return
    fi
    log_warn "Установлена версия Node.js $(node --version), требуется >= v${NODE_VERSION}"
    log_warn "Апгрейд Node меняет ABI — нативные модули (better-sqlite3 у 9router и др.)"
    log_warn "нужно будет пересобрать: npm install -g <пакет>"
  fi

  log_info "Устанавливаю Node.js ${NODE_VERSION}.x через NodeSource..."

  apt-get update -qq
  apt-get install -y curl gnupg

  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
  apt-get install -y nodejs

  log_success "Node.js установлен: $(node --version)"
  log_success "npm: $(npm --version)"
}

install_omniroute() {
  log_info "Устанавливаю omniroute глобально через npm..."

  if command -v omniroute &>/dev/null; then
    log_info "omniroute уже установлен, обновляю..."
    npm install -g omniroute || log_warn "Не удалось обновить omniroute"
  else
    npm install -g omniroute
  fi

  local bin_path
  bin_path="$(which omniroute 2>/dev/null || echo '/usr/bin/omniroute')"
  log_success "omniroute установлен: ${bin_path}"
  log_info "Версия: $(omniroute --version 2>/dev/null || echo 'неизвестна')"
}

# --- Генерация env-файла с секретами (идемпотентно: не перезатирает существующий) ---
create_env_file() {
  mkdir -p "${ENV_DIR}" "${DATA_DIR}"

  if [ -f "${ENV_FILE}" ]; then
    log_info "Файл окружения уже существует, секреты не трогаю: ${ENV_FILE}"
    return
  fi

  log_info "Генерирую секреты и файл окружения: ${ENV_FILE}"

  local jwt_secret api_key_secret storage_key ws_bridge_secret initial_password
  jwt_secret="$(openssl rand -base64 48 | tr -d '\n')"
  api_key_secret="$(openssl rand -hex 32)"
  storage_key="$(openssl rand -hex 32)"
  ws_bridge_secret="$(openssl rand -base64 32 | tr -d '\n')"
  initial_password="$(openssl rand -base64 18 | tr -d '\n/+=' | cut -c1-20)"

  umask 077
  cat > "${ENV_FILE}" <<EOF
# OmniRoute — окружение службы (сгенерировано install-omniroute.sh)
# Права 0600. Секреты менять только осознанно — смена ключей шифрования
# сделает существующую БД/сохранённые API-ключи нечитаемыми.
NODE_ENV=production

# --- Сеть ---
HOST=${OMNIROUTE_HOST}
PORT=${OMNIROUTE_PORT}
LIVE_WS_PORT=${OMNIROUTE_WS_PORT}
LIVE_WS_HOST=${OMNIROUTE_HOST}

# --- Хранилище ---
DATA_DIR=${DATA_DIR}

# --- Обязательные секреты ---
JWT_SECRET=${jwt_secret}
API_KEY_SECRET=${api_key_secret}
STORAGE_ENCRYPTION_KEY=${storage_key}
OMNIROUTE_WS_BRIDGE_SECRET=${ws_bridge_secret}

# Стартовый пароль администратора дашборда (сменить после первого входа:
# Dashboard -> Settings -> Security).
INITIAL_PASSWORD=${initial_password}
EOF
  chmod 0600 "${ENV_FILE}"

  log_success "Файл окружения создан"
  log_warn "Стартовый пароль администратора OmniRoute: ${initial_password}"
  log_warn "Сохраните его и смените после первого входа (Dashboard -> Settings -> Security)."
}

install_systemd_unit() {
  log_info "Устанавливаю systemd unit..."

  if [ ! -f "${SYSTEMD_TEMPLATE}" ]; then
    log_error "Не найден шаблон unit-файла: ${SYSTEMD_TEMPLATE}"
    exit 1
  fi

  local bin_path
  bin_path="$(which omniroute 2>/dev/null || echo '/usr/bin/omniroute')"

  sed "s|__BIN_PATH__|${bin_path}|g" "${SYSTEMD_TEMPLATE}" > "/etc/systemd/system/${SERVICE_NAME}.service"

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"
  log_success "Systemd unit установлен и включён"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  install_deps
  install_nodejs
  install_omniroute
  create_env_file
  install_systemd_unit

  systemctl restart "${SERVICE_NAME}.service"
  sleep 3

  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    log_success "Служба ${SERVICE_NAME} запущена!"
    log_info "Веб-интерфейс: http://localhost:${OMNIROUTE_PORT}"
  else
    log_warn "Служба не запустилась. Проверьте: journalctl -u ${SERVICE_NAME} -n 30"
  fi

  local desktop_src="${DESKTOP_DIR}/omniroute.desktop"
  if [ -f "${desktop_src}" ] && [ -d /usr/share/applications ]; then
    sed 's/\r$//' "${desktop_src}" > /usr/share/applications/omniroute.desktop
    log_success "Ярлык добавлен в меню: OmniRoute"
  fi
}

main "$@"
