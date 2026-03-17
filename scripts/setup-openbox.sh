#!/usr/bin/env bash
# =============================================================================
# Настройка Openbox + tint2 как Desktop Environment для xrdp
# Требует предварительной установки xrdp (setup-xrdp.sh)
# =============================================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/rsyuzyov/aiproxy/master"
INSTALL_DIR="${HOME}/aiproxy"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[openbox]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[openbox]${NC} $*"; }
log_error()   { echo -e "${RED}[openbox]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[openbox] OK:${NC} $*"; }

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_packages() {
  log_info "Устанавливаю openbox, tint2, xterm..."
  apt-get update -qq
  apt-get install -y -qq \
    openbox \
    tint2 \
    xterm

  log_success "Пакеты openbox установлены"
}

configure_startwm() {
  log_info "Настраиваю /etc/xrdp/startwm.sh (openbox-session)..."

  if [ ! -f "/etc/xrdp/startwm.sh.bak_orig" ]; then
    cp "/etc/xrdp/startwm.sh" "/etc/xrdp/startwm.sh.bak_orig" 2>/dev/null || true
  fi

  cat > "/etc/xrdp/startwm.sh" <<'EOF'
#!/bin/sh
# XRDP session startup — Openbox

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
[ -d "$XDG_RUNTIME_DIR" ] || { mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"; }

export DISPLAY=${DISPLAY:-:10}
export DESKTOP_SESSION=openbox
export XDG_CURRENT_DESKTOP=Openbox

exec dbus-launch --exit-with-session openbox-session
EOF

  chmod +x "/etc/xrdp/startwm.sh"
  log_success "startwm.sh → openbox-session"
}

configure_tint2() {
  log_info "Настраиваю tint2 (конфиг из репозитория)..."

  local cfg_dir="/etc/xdg/tint2"
  mkdir -p "${cfg_dir}"

  if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_RAW}/configs/tint2rc" -o "${cfg_dir}/tint2rc" 2>/dev/null && \
      log_success "tint2rc загружен из репозитория" || true
  elif command -v wget &>/dev/null; then
    wget -qO "${cfg_dir}/tint2rc" "${REPO_RAW}/configs/tint2rc" 2>/dev/null && \
      log_success "tint2rc загружен из репозитория" || true
  fi

  if [ ! -s "${cfg_dir}/tint2rc" ] && [ -f "${INSTALL_DIR}/configs/tint2rc" ]; then
    cp "${INSTALL_DIR}/configs/tint2rc" "${cfg_dir}/tint2rc"
    log_success "tint2rc скопирован из локального репозитория"
  fi

  [ -s "${cfg_dir}/tint2rc" ] && \
    log_success "tint2 настроен: ${cfg_dir}/tint2rc" || \
    log_warn "Не удалось установить конфиг tint2, будет использован дефолтный"
}

configure_openbox_menu() {
  log_info "Настраиваю меню openbox..."

  local ob_dir="/etc/xdg/openbox"
  mkdir -p "${ob_dir}"

  cat > "${ob_dir}/menu.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">

  <menu id="root-menu" label="Меню">
    <item label="Терминал">
      <action name="Execute"><command>xterm</command></action>
    </item>
    <separator/>
    <item label="Firefox">
      <action name="Execute"><command>firefox-esr</command></action>
    </item>
    <item label="cliproxy-api (управление)">
      <action name="Execute"><command>firefox-esr http://127.0.0.1:8317/management.html</command></action>
    </item>
    <separator/>
    <item label="ProxyBridge GUI">
      <action name="Execute"><command>ProxyBridgeGUI</command></action>
    </item>
    <separator/>
    <menu id="sys-menu" label="Система">
      <item label="Перезапустить openbox">
        <action name="Reconfigure"/>
      </item>
      <item label="Завершить сессию">
        <action name="Exit"><prompt>no</prompt></action>
      </item>
    </menu>
  </menu>

</openbox_menu>
EOF

  log_success "menu.xml настроен"
}

configure_xresources() {
  log_info "Настраиваю ~/.Xresources (xterm: ПКМ = вставить из буфера)..."

  cat > /root/.Xresources << 'EOF'
! XTerm — правая кнопка вставляет из буфера обмена
XTerm*selectToClipboard: true
XTerm*VT100.Translations: #override \
  <Btn3Down>: insert-selection(CLIPBOARD,PRIMARY) \n \
  Ctrl <Key>V: insert-selection(CLIPBOARD) \n \
  Shift <Key>Insert: insert-selection(CLIPBOARD,PRIMARY)
EOF

  log_success "~/.Xresources настроен"
}

configure_openbox_autostart() {
  log_info "Настраиваю автозапуск Openbox..."

  local autostart_dir="/etc/xdg/openbox"
  mkdir -p "${autostart_dir}"

  cat > "${autostart_dir}/autostart" <<'EOF'
# Openbox autostart — запускается при старте RDP-сессии

# Фон рабочего стола
xsetroot -solid "#2e3440" &

# Переключение раскладки Alt+Shift (us/ru)
# sleep 2: xrdpkeyb-драйвер переинициализирует раскладку после RDP-подключения
(sleep 2 && setxkbmap -layout us,ru -option grp:alt_shift_toggle) &

# X ресурсы (xterm: ПКМ = вставить из буфера)
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources &

# Панель задач
tint2 &
EOF

  log_success "Openbox autostart настроен"
}

restart_xrdp() {
  log_info "Перезапускаю xrdp для применения изменений..."
  systemctl restart xrdp xrdp-sesman 2>/dev/null || true
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  install_packages
  configure_startwm
  configure_tint2
  configure_openbox_menu
  configure_xresources
  configure_openbox_autostart
  restart_xrdp

  echo ""
  log_success "Openbox + tint2 настроены!"
  log_info "Подключитесь по RDP (порт 3389)"
}

main "$@"
