#!/usr/bin/env bash
# =============================================================================
# AIProxy Setup Master Installer
# https://github.com/YOUR_GITHUB_USER/aiproxy
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/rsyuzyov/aiproxy"
REPO_RAW="https://raw.githubusercontent.com/rsyuzyov/aiproxy/master"
INSTALL_DIR="${HOME}/aiproxy"

# --- Цвета ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${BLUE}==>${NC}${BOLD} $*${NC}"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# --- Проверка root ---
require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Этот скрипт необходимо запускать от имени root."
    exit 1
  fi
}

# --- Локали (для корректной кириллицы и стабильной работы apt/debconf) ---
ensure_locales() {
  log_step "Настройка локалей (en_US.UTF-8 и ru_RU.UTF-8)"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq locales

  if grep -q '^#\s*en_US.UTF-8 UTF-8' /etc/locale.gen; then
    sed -i 's/^#\s*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  elif ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
    echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
  fi

  if grep -q '^#\s*ru_RU.UTF-8 UTF-8' /etc/locale.gen; then
    sed -i 's/^#\s*ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
  elif ! grep -q '^ru_RU.UTF-8 UTF-8' /etc/locale.gen; then
    echo 'ru_RU.UTF-8 UTF-8' >> /etc/locale.gen
  fi

  locale-gen en_US.UTF-8 ru_RU.UTF-8 >/dev/null
  update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8

  export LANG=ru_RU.UTF-8
  export LC_ALL=ru_RU.UTF-8

  log_success "Локали настроены: LANG=${LANG}, LC_ALL=${LC_ALL}"
}

# --- Парсинг аргументов командной строки ---
# Режим без интерактива: install.sh --cliproxy --9router --xrdp --firefox
NON_INTERACTIVE=false
DO_CLIPROXY=false
DO_9ROUTER=false
DO_XRDP=false
DO_FIREFOX=false
DO_BRAVE=false
DO_REDSOCKS=false

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --non-interactive|-y) NON_INTERACTIVE=true ;;
      --all)
        DO_CLIPROXY=true; DO_9ROUTER=true; DO_XRDP=true
        DO_FIREFOX=true; DO_BRAVE=false; DO_REDSOCKS=true ;;
      --cliproxy)  DO_CLIPROXY=true ;;
      --9router)   DO_9ROUTER=true ;;
      --xrdp)      DO_XRDP=true ;;
      --firefox)   DO_FIREFOX=true ;;
      --brave)     DO_BRAVE=true ;;
      --redsocks)  DO_REDSOCKS=true ;;
      --help|-h)   show_help; exit 0 ;;
      *) log_warn "Неизвестный аргумент: $arg" ;;
    esac
  done
}

show_help() {
  cat <<EOF
${BOLD}AIProxy Setup Installer${NC}

Использование:
  install.sh [OPTIONS]

Опции:
  --all               Установить всё (кроме Brave)
  --cliproxy          Установить службу cliproxy-api
  --9router           Установить службу 9router
  --xrdp              Настроить xrdp + openbox (RDP-доступ)
  --firefox           Установить Firefox ESR
  --brave             Установить Brave Browser
  --redsocks          Настроить redsocks (прокси)
  --non-interactive   Неинтерактивный режим (требует явных флагов)
  -y                  Синоним --non-interactive
  --help              Показать эту справку

Примеры:
  # Интерактивный мастер:
  bash install.sh

  # Установить всё автоматически:
  bash install.sh --all -y

  # Только cliproxy-api и xrdp:
  bash install.sh --cliproxy --xrdp -y
EOF
}

# --- Установка git и клонирование репозитория ---
ensure_repo() {
  log_step "Подготовка репозитория"

  # Установить git если нужно
  if ! command -v git &>/dev/null; then
    log_info "Устанавливаю git..."
    apt-get update -qq
    apt-get install -y -qq git
    log_success "git установлен"
  fi

  if [ -d "${INSTALL_DIR}/.git" ]; then
    log_info "Репозиторий уже существует: ${INSTALL_DIR}"
    log_info "Обновляю..."
    git -C "${INSTALL_DIR}" pull --ff-only || log_warn "Не удалось обновить репозиторий"
  else
    log_info "Клонирую репозиторий в ${INSTALL_DIR}..."
    git clone "${REPO_URL}.git" "${INSTALL_DIR}"
    log_success "Репозиторий клонирован"
  fi

  # Убедиться что скрипты исполняемые
  find "${INSTALL_DIR}/scripts" -name "*.sh" -exec chmod +x {} \;
  chmod +x "${INSTALL_DIR}/install.sh" 2>/dev/null || true
}

# --- Интерактивное меню ---
interactive_menu() {
  clear
  cat <<EOF
${BOLD}${CYAN}
╔══════════════════════════════════════════╗
║       AIProxy Setup Wizard               ║
╚══════════════════════════════════════════╝
${NC}
Выберите компоненты для установки:
(Нажмите Enter для подтверждения каждого пункта)

EOF

  ask_yn "Установить cliproxy-api (AI-прокси сервис)?" && DO_CLIPROXY=true || true
  ask_yn "Установить 9router (Node.js роутер)?" && DO_9ROUTER=true || true
  ask_yn "Настроить xrdp + openbox (RDP-доступ)?" && DO_XRDP=true || true
  ask_yn "Установить Firefox ESR?" && DO_FIREFOX=true || true
  ask_yn "Установить Brave Browser?" && DO_BRAVE=true || true
  ask_yn "Настроить redsocks (SOCKS5 прокси)?" && DO_REDSOCKS=true || true

  echo ""
  log_step "Выбранные компоненты"
  [ "$DO_CLIPROXY" = "true" ] && log_info "✓ cliproxy-api"
  [ "$DO_9ROUTER"  = "true" ] && log_info "✓ 9router"
  [ "$DO_XRDP"     = "true" ] && log_info "✓ xrdp + openbox"
  [ "$DO_FIREFOX"  = "true" ] && log_info "✓ Firefox ESR"
  [ "$DO_BRAVE"    = "true" ] && log_info "✓ Brave Browser"
  [ "$DO_REDSOCKS" = "true" ] && log_info "✓ redsocks"

  if [ "$DO_CLIPROXY" = "false" ] && [ "$DO_9ROUTER" = "false" ] && \
     [ "$DO_XRDP" = "false" ] && [ "$DO_FIREFOX" = "false" ] && \
     [ "$DO_BRAVE" = "false" ] && [ "$DO_REDSOCKS" = "false" ]; then
    log_warn "Ничего не выбрано. Выход."
    exit 0
  fi

  echo ""
  ask_yn "Начать установку?" || { log_warn "Отменено."; exit 0; }
}

ask_yn() {
  local prompt="$1"
  local answer
  printf "${YELLOW}?${NC} %s [y/N] " "$prompt"
  read -r answer
  case "${answer,,}" in
    y|yes|д|да) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Запрос параметров redsocks ---
ask_redsocks_params() {
  if [ "$DO_REDSOCKS" = "true" ]; then
    echo ""
    log_step "Параметры SOCKS5-прокси для redsocks"

    printf "  IP-адрес прокси: "
    read -r PROXY_IP

    printf "  Порт прокси [1080]: "
    read -r PROXY_PORT
    PROXY_PORT="${PROXY_PORT:-1080}"

    printf "  Логин: "
    read -r PROXY_LOGIN

    printf "  Пароль: "
    read -rs PROXY_PASS
    echo ""

    printf "  Локальный порт redsocks [12345]: "
    read -r LOCAL_PORT
    LOCAL_PORT="${LOCAL_PORT:-12345}"

    export PROXY_IP PROXY_PORT PROXY_LOGIN PROXY_PASS LOCAL_PORT
  fi
}

# --- Запуск нужных скриптов ---
run_installations() {
  local scripts_dir="${INSTALL_DIR}/scripts"

  if [ "$DO_CLIPROXY" = "true" ]; then
    log_step "Установка cliproxy-api"
    bash "${scripts_dir}/install-cliproxy-api.sh"
  fi

  if [ "$DO_9ROUTER" = "true" ]; then
    log_step "Установка 9router"
    bash "${scripts_dir}/install-9router.sh"
  fi

  if [ "$DO_XRDP" = "true" ]; then
    log_step "Настройка xrdp + openbox"
    bash "${scripts_dir}/setup-xrdp.sh"
  fi

  if [ "$DO_FIREFOX" = "true" ]; then
    log_step "Установка Firefox ESR"
    bash "${scripts_dir}/install-firefox.sh"
  fi

  if [ "$DO_BRAVE" = "true" ]; then
    log_step "Установка Brave Browser"
    bash "${scripts_dir}/install-brave.sh"
  fi

  if [ "$DO_REDSOCKS" = "true" ]; then
    log_step "Настройка redsocks"
    bash "${scripts_dir}/setup-redsocks.sh" \
      "${PROXY_IP}" "${PROXY_PORT}" "${PROXY_LOGIN}" "${PROXY_PASS}" "${LOCAL_PORT}"
  fi
}

# --- Итоговый отчёт ---
show_summary() {
  echo ""
  cat <<EOF
${BOLD}${GREEN}
╔══════════════════════════════════════════╗
║         Установка завершена!             ║
╚══════════════════════════════════════════╝
${NC}
Установленные компоненты:
EOF
  [ "$DO_CLIPROXY" = "true" ] && echo -e "  ${GREEN}✓${NC} cliproxy-api  (http://localhost:8317)"
  [ "$DO_9ROUTER"  = "true" ] && echo -e "  ${GREEN}✓${NC} 9router       (http://localhost:20128)"
  [ "$DO_XRDP"     = "true" ] && echo -e "  ${GREEN}✓${NC} xrdp          (RDP порт 3389)"
  [ "$DO_FIREFOX"  = "true" ] && echo -e "  ${GREEN}✓${NC} Firefox ESR"
  [ "$DO_BRAVE"    = "true" ] && echo -e "  ${GREEN}✓${NC} Brave Browser"
  [ "$DO_REDSOCKS" = "true" ] && echo -e "  ${GREEN}✓${NC} redsocks      (управление: ${INSTALL_DIR}/scripts/proxy-toggle.sh)"

  cat <<EOF

${BOLD}Полезные команды:${NC}
  ${INSTALL_DIR}/scripts/proxy-toggle.sh on|off|status    — включение/выключение прокси
  ${INSTALL_DIR}/scripts/setup-redsocks.sh IP PORT USER PASS — обновление настроек прокси

Скрипты доступны в: ${INSTALL_DIR}/scripts/
EOF
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root
  ensure_locales

  # Если запускаем через pipe (wget|bash), нет аргументов → скачать и перезапустить
  if [ "$#" -eq 0 ] && [ ! -d "${INSTALL_DIR}/.git" ]; then
    ensure_repo
    exec bash "${INSTALL_DIR}/install.sh" "$@"
  fi

  parse_args "$@"

  # Если репозиторий уже есть — просто запускаем скрипты из него
  # Если нет — клонируем сначала
  if [ ! -d "${INSTALL_DIR}/.git" ]; then
    ensure_repo
  fi

  if [ "$NON_INTERACTIVE" = "false" ]; then
    interactive_menu
    ask_redsocks_params
  else
    # В неинтерактивном режиме redsocks параметры берём из env или скипаем
    if [ "$DO_REDSOCKS" = "true" ]; then
      PROXY_IP="${PROXY_IP:-}"
      PROXY_PORT="${PROXY_PORT:-1080}"
      PROXY_LOGIN="${PROXY_LOGIN:-}"
      PROXY_PASS="${PROXY_PASS:-}"
      LOCAL_PORT="${LOCAL_PORT:-12345}"

      if [ -z "$PROXY_IP" ] || [ -z "$PROXY_LOGIN" ]; then
        log_error "Для --redsocks в неинтерактивном режиме нужно задать переменные:"
        log_error "  PROXY_IP, PROXY_PORT, PROXY_LOGIN, PROXY_PASS"
        log_error "Пример: PROXY_IP=1.2.3.4 PROXY_PORT=1080 PROXY_LOGIN=user PROXY_PASS=pass bash install.sh --redsocks -y"
        exit 1
      fi
    fi
  fi

  run_installations
  show_summary
}

main "$@"
