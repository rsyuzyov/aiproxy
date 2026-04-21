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
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

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
  # Пропустить если обе локали уже сгенерированы
  if locale -a 2>/dev/null | grep -q 'en_US.utf8' && \
     locale -a 2>/dev/null | grep -q 'ru_RU.utf8'; then
    export LANG=ru_RU.UTF-8
    export LC_ALL=ru_RU.UTF-8
    log_success "Локали уже настроены, пропускаю"
    return
  fi

  log_step "Настройка локалей (en_US.UTF-8 и ru_RU.UTF-8)"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y locales

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
DO_OPENBOX=false
DO_LXQT=false
DO_FIREFOX=false
DO_BRAVE=false
DO_GOST=false
DO_AMNEZIA=false
DO_PROXYBRIDGE=false
DO_ANTIGRAVITY=false
DO_CLAUDE_CODE=false
DO_COCKPIT_TOOLS=false
DO_VSCODE=false
DO_SINGBOX=false
DO_XRAY=false
DO_3XUI=false
DO_OPENCODE=false
DO_GATE=false

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --non-interactive|-y) NON_INTERACTIVE=true ;;
      --aiproxy)
        DO_XRDP=true; DO_LXQT=true; DO_CLIPROXY=true; DO_9ROUTER=true
        DO_FIREFOX=true; DO_COCKPIT_TOOLS=true; DO_PROXYBRIDGE=true ;;
      --gate)
        DO_GATE=true; DO_SINGBOX=true; DO_XRAY=true ;;
      --cliproxy)        DO_CLIPROXY=true ;;
      --9router)         DO_9ROUTER=true ;;
      --xrdp)            DO_XRDP=true ;;
      --openbox)         DO_OPENBOX=true ;;
      --lxqt)            DO_LXQT=true ;;
      --firefox)         DO_FIREFOX=true ;;
      --brave)           DO_BRAVE=true ;;
      --gost)            DO_GOST=true ;;
      --amnezia)         DO_AMNEZIA=true ;;
      --proxybridge)     DO_PROXYBRIDGE=true ;;
      --antigravity)     DO_ANTIGRAVITY=true ;;
      --claude-code)     DO_CLAUDE_CODE=true ;;
      --cockpit-tools)   DO_COCKPIT_TOOLS=true ;;
      --vscode)          DO_VSCODE=true ;;
      --opencode)        DO_OPENCODE=true ;;
      --sing-box|--singbox) DO_SINGBOX=true ;;
      --xray)            DO_XRAY=true ;;
      --3x-ui|--3xui)    DO_3XUI=true ;;
      --help|-h)         show_help; exit 0 ;;
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
  ${BOLD}Мета-наборы:${NC}
  --aiproxy           Набор AIProxy: xrdp + LXQt + cliproxy-api + 9router + Firefox + Cockpit Tools + ProxyBridge
  --gate              Шлюз: sing-box (SOCKS5 :1080 + TUN) + xray (SOCKS5 :8080), outbound=direct

  ${BOLD}Компоненты:${NC}
  --cliproxy          Установить службу cliproxy-api
  --gost              Установить gost (SOCKS5 прокси для всей сети, замена redsocks)
  --proxybridge       Установить ProxyBridge (TCP+UDP прокси per-process)
  --9router           Установить службу 9router
  --sing-box          Установить sing-box (нейтральный конфиг; для шлюза используй --gate)
  --xray              Установить Xray (нейтральный конфиг; для шлюза используй --gate)
  --3x-ui             Установить 3x-ui (web-панель управления Xray, серверная часть)
  --xrdp              Установить xrdp-сервер (без Desktop Environment)
  --openbox           Настроить Openbox + tint2 как DE для xrdp
  --lxqt              Настроить LXQt как DE для xrdp (только Debian 13)
  --firefox           Установить Firefox ESR
  --brave             Установить Brave Browser
  --amnezia           Установить AmneziaWG VPN-клиент
  --antigravity       Установить Google Antigravity IDE
  --claude-code       Установить Claude Code CLI (Anthropic)
  --opencode          Установить OpenCode (CLI + Desktop)
  --cockpit-tools     Установить Cockpit Tools (менеджер аккаунтов AI IDE)
  --vscode            Установить Visual Studio Code
  --non-interactive   Неинтерактивный режим (требует явных флагов)
  -y                  Синоним --non-interactive
  --help              Показать эту справку

Примеры:
  # Интерактивный мастер:
  bash install.sh

  # Набор AIProxy одной командой:
  bash install.sh --aiproxy -y

  # Поднять машину как шлюз:
  bash install.sh --gate -y

  # Только gost + ProxyBridge:
  bash install.sh --gost --proxybridge -y

  # AI-инструменты (Antigravity + Claude Code + OpenCode + Cockpit Tools):
  bash install.sh --antigravity --claude-code --opencode --cockpit-tools -y
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
  # Проверка: при запуске через pipe (wget|bash) /dev/tty нужен для интерактивного ввода
  if ! exec 3</dev/tty 2>/dev/null; then
    log_error "Невозможно открыть /dev/tty для интерактивного ввода."
    log_error "Используйте: wget -O install.sh ... && bash install.sh"
    log_error "Или передайте компоненты флагами: install.sh --cliproxy --xrdp -y"
    exit 1
  fi
  exec 3<&-

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

  echo -e "${BOLD}${CYAN}--- Мета-наборы ---${NC}"
  if ask_yn "Набор AIProxy (xrdp + LXQt + cliproxy-api + 9router + Firefox + Cockpit Tools + ProxyBridge)?"; then
    DO_XRDP=true; DO_LXQT=true; DO_CLIPROXY=true; DO_9ROUTER=true
    DO_FIREFOX=true; DO_COCKPIT_TOOLS=true; DO_PROXYBRIDGE=true
  fi
  if ask_yn "Набор GATE (sing-box + xray в режиме шлюза)?"; then
    DO_GATE=true; DO_SINGBOX=true; DO_XRAY=true
  fi

  echo ""
  echo -e "${BOLD}${CYAN}--- Отдельные компоненты ---${NC}"
  ask_yn "Установить cliproxy-api (AI-прокси сервис)?" && DO_CLIPROXY=true || true
  ask_yn "Установить gost (SOCKS5 прокси для всей сети)?" && DO_GOST=true || true
  ask_yn "Установить ProxyBridge (per-process TCP+UDP прокси)?" && DO_PROXYBRIDGE=true || true
  ask_yn "Установить 9router (Node.js роутер)?" && DO_9ROUTER=true || true
  ask_yn "Установить sing-box?" && DO_SINGBOX=true || true
  ask_yn "Установить Xray?" && DO_XRAY=true || true
  ask_yn "Установить 3x-ui (web-панель для Xray)?" && DO_3XUI=true || true
  ask_yn "Установить xrdp-сервер (RDP, порт 3389)?" && DO_XRDP=true || true
  ask_yn "Настроить Openbox + tint2 как рабочий стол?" && DO_OPENBOX=true || true
  ask_yn "Настроить LXQt как рабочий стол (Debian 13)?" && DO_LXQT=true || true
  ask_yn "Установить Firefox ESR?" && DO_FIREFOX=true || true
  ask_yn "Установить Brave Browser?" && DO_BRAVE=true || true
  ask_yn "Установить AmneziaWG VPN-клиент?" && DO_AMNEZIA=true || true

  echo ""
  echo -e "${BOLD}${CYAN}--- AI IDE инструменты ---${NC}"
  ask_yn "Установить Google Antigravity IDE?" && DO_ANTIGRAVITY=true || true
  ask_yn "Установить Claude Code CLI (Anthropic)?" && DO_CLAUDE_CODE=true || true
  ask_yn "Установить OpenCode (CLI + Desktop)?" && DO_OPENCODE=true || true
  ask_yn "Установить Cockpit Tools (менеджер аккаунтов AI IDE)?" && DO_COCKPIT_TOOLS=true || true
  ask_yn "Установить Visual Studio Code?" && DO_VSCODE=true || true

  echo ""
  log_step "Выбранные компоненты"
  [ "$DO_CLIPROXY"       = "true" ] && log_info "✓ cliproxy-api"
  [ "$DO_GOST"           = "true" ] && log_info "✓ gost"
  [ "$DO_PROXYBRIDGE"    = "true" ] && log_info "✓ ProxyBridge"
  [ "$DO_9ROUTER"        = "true" ] && log_info "✓ 9router"
  [ "$DO_SINGBOX"        = "true" ] && log_info "✓ sing-box$([ "$DO_GATE" = "true" ] && echo " (режим шлюза)")"
  [ "$DO_XRAY"           = "true" ] && log_info "✓ Xray$([ "$DO_GATE" = "true" ] && echo " (режим шлюза)")"
  [ "$DO_3XUI"           = "true" ] && log_info "✓ 3x-ui"
  [ "$DO_XRDP"           = "true" ] && log_info "✓ xrdp-сервер"
  [ "$DO_OPENBOX"        = "true" ] && log_info "✓ Openbox + tint2"
  [ "$DO_LXQT"           = "true" ] && log_info "✓ LXQt"
  [ "$DO_FIREFOX"        = "true" ] && log_info "✓ Firefox ESR"
  [ "$DO_BRAVE"          = "true" ] && log_info "✓ Brave Browser"
  [ "$DO_AMNEZIA"        = "true" ] && log_info "✓ AmneziaWG VPN"
  [ "$DO_ANTIGRAVITY"    = "true" ] && log_info "✓ Google Antigravity IDE"
  [ "$DO_CLAUDE_CODE"    = "true" ] && log_info "✓ Claude Code CLI"
  [ "$DO_OPENCODE"       = "true" ] && log_info "✓ OpenCode (CLI + Desktop)"
  [ "$DO_COCKPIT_TOOLS"  = "true" ] && log_info "✓ Cockpit Tools"
  [ "$DO_VSCODE"         = "true" ] && log_info "✓ Visual Studio Code"



  if [ "$DO_CLIPROXY" = "false" ] && [ "$DO_GOST" = "false" ] && \
     [ "$DO_PROXYBRIDGE" = "false" ] && \
     [ "$DO_9ROUTER" = "false" ] && [ "$DO_XRDP" = "false" ] && \
     [ "$DO_SINGBOX" = "false" ] && [ "$DO_XRAY" = "false" ] && \
     [ "$DO_3XUI" = "false" ] && \
     [ "$DO_OPENBOX" = "false" ] && [ "$DO_LXQT" = "false" ] && \
     [ "$DO_FIREFOX" = "false" ] && [ "$DO_BRAVE" = "false" ] && \
     [ "$DO_AMNEZIA" = "false" ] && \
     [ "$DO_ANTIGRAVITY" = "false" ] && [ "$DO_CLAUDE_CODE" = "false" ] && \
     [ "$DO_OPENCODE" = "false" ] && \
     [ "$DO_COCKPIT_TOOLS" = "false" ] && \
     [ "$DO_VSCODE" = "false" ]; then
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
  read -r answer </dev/tty
  case "${answer,,}" in
    y|yes|д|да) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Запуск нужных скриптов ---
run_installations() {
  local scripts_dir="${INSTALL_DIR}/scripts"

  run_component_script() {
    local script_path="$1"
    local script_name
    script_name="$(basename "${script_path}")"

    local attempt=1
    local max_attempts=2
    local rc=0

    while true; do
      set +e
      bash "${script_path}"
      rc=$?
      set -e

      if [ "${rc}" -eq 0 ]; then
        return 0
      fi

      if [ "${rc}" -eq 137 ] && [ "${attempt}" -lt "${max_attempts}" ]; then
        log_warn "${script_name}: завершился SIGKILL (exit 137), попытка ${attempt}/${max_attempts}; повтор через 5 секунд..."
        sleep 5
        attempt=$((attempt + 1))
        continue
      fi

      return "${rc}"
    done
  }

  if [ "$DO_CLIPROXY" = "true" ]; then
    log_step "Установка cliproxy-api"
    run_component_script "${scripts_dir}/install-cliproxy-api.sh"
  fi

  if [ "$DO_GOST" = "true" ]; then
    log_step "Установка gost"
    run_component_script "${scripts_dir}/setup-gost.sh"
  fi

  if [ "$DO_PROXYBRIDGE" = "true" ]; then
    log_step "Установка ProxyBridge"
    run_component_script "${scripts_dir}/install-proxybridge.sh"
  fi

  if [ "$DO_9ROUTER" = "true" ]; then
    log_step "Установка 9router"
    run_component_script "${scripts_dir}/install-9router.sh"
  fi

  if [ "$DO_SINGBOX" = "true" ]; then
    log_step "Установка sing-box$([ "$DO_GATE" = "true" ] && echo " (режим шлюза)")"
    GATE_MODE="$([ "$DO_GATE" = "true" ] && echo 1 || echo 0)" \
      run_component_script "${scripts_dir}/install-singbox.sh"
  fi

  if [ "$DO_XRAY" = "true" ]; then
    log_step "Установка Xray$([ "$DO_GATE" = "true" ] && echo " (режим шлюза)")"
    GATE_MODE="$([ "$DO_GATE" = "true" ] && echo 1 || echo 0)" \
      run_component_script "${scripts_dir}/install-xray.sh"
  fi

  if [ "$DO_3XUI" = "true" ]; then
    log_step "Установка 3x-ui"
    run_component_script "${scripts_dir}/install-3xui.sh"
  fi

  if [ "$DO_XRDP" = "true" ]; then
    log_step "Установка xrdp-сервера"
    run_component_script "${scripts_dir}/setup-xrdp.sh"
  fi

  if [ "$DO_OPENBOX" = "true" ]; then
    log_step "Настройка Openbox + tint2"
    run_component_script "${scripts_dir}/setup-openbox.sh"
  fi

  if [ "$DO_LXQT" = "true" ]; then
    log_step "Настройка LXQt"
    run_component_script "${scripts_dir}/setup-lxqt.sh"
  fi

  if [ "$DO_FIREFOX" = "true" ]; then
    log_step "Установка Firefox ESR"
    run_component_script "${scripts_dir}/install-firefox.sh"
  fi

  if [ "$DO_BRAVE" = "true" ]; then
    log_step "Установка Brave Browser"
    run_component_script "${scripts_dir}/install-brave.sh"
  fi



  if [ "$DO_AMNEZIA" = "true" ]; then
    log_step "Установка AmneziaWG VPN-клиента"
    run_component_script "${scripts_dir}/install-amnezia.sh"
  fi

  if [ "$DO_ANTIGRAVITY" = "true" ]; then
    log_step "Установка Google Antigravity IDE"
    run_component_script "${scripts_dir}/install-antigravity.sh"
  fi

  if [ "$DO_CLAUDE_CODE" = "true" ]; then
    log_step "Установка Claude Code CLI"
    run_component_script "${scripts_dir}/install-claude-code.sh"
  fi

  if [ "$DO_OPENCODE" = "true" ]; then
    log_step "Установка OpenCode (CLI + Desktop)"
    run_component_script "${scripts_dir}/install-opencode.sh"
  fi

  if [ "$DO_COCKPIT_TOOLS" = "true" ]; then
    log_step "Установка Cockpit Tools"
    run_component_script "${scripts_dir}/install-cockpit-tools.sh"
  fi

  if [ "$DO_VSCODE" = "true" ]; then
    log_step "Установка Visual Studio Code"
    run_component_script "${scripts_dir}/install-vscode.sh"
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
  [ "$DO_CLIPROXY"     = "true" ] && echo -e "  ${GREEN}✓${NC} cliproxy-api  (http://localhost:8317)"
  [ "$DO_GOST"         = "true" ] && echo -e "  ${GREEN}✓${NC} gost          (SOCKS5 на 0.0.0.0:1080, управление: ${INSTALL_DIR}/scripts/gost-toggle.sh)"
  if [ "$DO_PROXYBRIDGE" = "true" ]; then
    if /usr/local/bin/ProxyBridge --help &>/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${NC} ProxyBridge   (ProxyBridge --help | ProxyBridgeGUI)"
    else
      echo -e "  ${YELLOW}⚠${NC} ProxyBridge   (установлен, но не поддерживается на этой ОС — требуется glibc >= 2.38)"
    fi
  fi
  [ "$DO_9ROUTER"      = "true" ] && echo -e "  ${GREEN}✓${NC} 9router       (http://localhost:20128)"
  if [ "$DO_SINGBOX"   = "true" ]; then
    if [ "$DO_GATE" = "true" ]; then
      echo -e "  ${GREEN}✓${NC} sing-box      (SOCKS5 :1080 + TUN-шлюз, конфиг: /etc/sing-box/config.json)"
    else
      echo -e "  ${GREEN}✓${NC} sing-box      (конфиг: /etc/sing-box/config.json)"
    fi
  fi
  if [ "$DO_XRAY"      = "true" ]; then
    if [ "$DO_GATE" = "true" ]; then
      echo -e "  ${GREEN}✓${NC} Xray          (SOCKS5 :8080, outbound=direct, конфиг: /usr/local/etc/xray/config.json)"
    else
      echo -e "  ${GREEN}✓${NC} Xray          (конфиг: /usr/local/etc/xray/config.json)"
    fi
  fi
  [ "$DO_3XUI"         = "true" ] && echo -e "  ${GREEN}✓${NC} 3x-ui         (web-панель, команда: x-ui)"
  [ "$DO_XRDP"         = "true" ] && echo -e "  ${GREEN}✓${NC} xrdp-сервер   (RDP порт 3389)"
  [ "$DO_OPENBOX"      = "true" ] && echo -e "  ${GREEN}✓${NC} Openbox + tint2"
  [ "$DO_LXQT"        = "true" ] && echo -e "  ${GREEN}✓${NC} LXQt"
  [ "$DO_FIREFOX"      = "true" ] && echo -e "  ${GREEN}✓${NC} Firefox ESR"
  [ "$DO_BRAVE"        = "true" ] && echo -e "  ${GREEN}✓${NC} Brave Browser"
  [ "$DO_AMNEZIA"        = "true" ] && echo -e "  ${GREEN}✓${NC} AmneziaWG       (конфиг: /etc/amnezia/amneziawg/)"
  [ "$DO_ANTIGRAVITY"   = "true" ] && echo -e "  ${GREEN}✓${NC} Antigravity IDE  (команда: antigravity)"
  [ "$DO_CLAUDE_CODE"   = "true" ] && echo -e "  ${GREEN}✓${NC} Claude Code      (команда: claude)"
  [ "$DO_OPENCODE"       = "true" ] && echo -e "  ${GREEN}✓${NC} OpenCode         (CLI: opencode, Desktop: opencode-desktop)"
  [ "$DO_COCKPIT_TOOLS" = "true" ] && echo -e "  ${GREEN}✓${NC} Cockpit Tools    (команда: cockpit-tools)"
  [ "$DO_VSCODE"        = "true" ] && echo -e "  ${GREEN}✓${NC} VS Code          (команда: code)"

  cat <<EOF

${BOLD}Полезные команды:${NC}
  ${INSTALL_DIR}/scripts/gost-toggle.sh set IP PORT USER PASS — задать upstream прокси
  ${INSTALL_DIR}/scripts/gost-toggle.sh on|off|status         — включение/выключение/статус

  ${INSTALL_DIR}/scripts/setup-amnezia-connection.sh /path/to/amnezia.conf  — настроить VPN-подключение

Скрипты доступны в: ${INSTALL_DIR}/scripts/

${BOLD}Автообновление (ежедневно в 05:00):${NC}
EOF
  [ "$DO_CLIPROXY" = "true" ] && echo -e "  ${GREEN}✓${NC} cliproxy-api-updater.timer  (journalctl -u cliproxy-api-updater.service)"
  [ "$DO_9ROUTER"  = "true" ] && echo -e "  ${GREEN}✓${NC} 9router-updater.timer       (journalctl -u 9router-updater.service)"
  echo -e "\n  Расписание: ${CYAN}systemctl list-timers --all | grep updater${NC}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root
  # pct exec и подобные среды могут не включать /usr/local/bin в PATH
  export PATH="/usr/local/sbin:/usr/local/bin:${PATH}"
  export DEBIAN_FRONTEND=noninteractive
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

  fi

  run_installations
  show_summary
}

main "$@"
