#!/usr/bin/env bash
# =============================================================================
# Настройка xrdp + openbox + tint2 для RDP-доступа
# Особенности:
#  - Всегда английская раскладка (US) при входе
#  - openbox-session через dbus-launch
#  - Вертикальная панель tint2 слева (конфиг: configs/tint2rc)
#  - Контекстное меню openbox по ПКМ на рабочем столе
# =============================================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/rsyuzyov/aiproxy/master"
INSTALL_DIR="${HOME}/aiproxy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[xrdp]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[xrdp]${NC} $*"; }
log_error()   { echo -e "${RED}[xrdp]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[xrdp] OK:${NC} $*"; }

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

install_packages() {
  log_info "Обновляю пакетный менеджер..."
  apt-get update -qq

  log_info "Устанавливаю xrdp, openbox, tint2, dbus-x11..."
  apt-get install -y -qq \
    xrdp \
    xorgxrdp \
    openbox \
    tint2 \
    dbus-x11 \
    x11-xserver-utils \
    x11-utils \
    xfonts-base \
    xterm \
    bash-completion

  log_success "Пакеты установлены"
}

configure_startwm() {
  log_info "Настраиваю /etc/xrdp/startwm.sh..."

  # Сохранить резервную копию если не существует
  if [ ! -f "/etc/xrdp/startwm.sh.bak_orig" ]; then
    cp "/etc/xrdp/startwm.sh" "/etc/xrdp/startwm.sh.bak_orig" 2>/dev/null || true
  fi

  cat > "/etc/xrdp/startwm.sh" <<'EOF'
#!/bin/sh
# XRDP session startup script

# XDG runtime dir
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
[ -d "$XDG_RUNTIME_DIR" ] || { mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"; }

# DISPLAY задаётся xrdp/sesman через env; fallback на :10
export DISPLAY=${DISPLAY:-:10}

export DESKTOP_SESSION=openbox
export XDG_CURRENT_DESKTOP=Openbox

exec dbus-launch --exit-with-session openbox-session
EOF

  chmod +x "/etc/xrdp/startwm.sh"
  log_success "startwm.sh настроен"
}

configure_keyboard_en() {
  log_info "Настраиваю раскладки клавиатуры (US + RU, переключение Alt+Shift)..."

  # /etc/default/keyboard — системная раскладка по умолчанию US
  cat > "/etc/default/keyboard" <<'EOF'
# KEYBOARD CONFIGURATION FILE
XKBMODEL="pc105"
XKBLAYOUT="us,ru"
XKBVARIANT=","
XKBOPTIONS="grp:alt_shift_toggle"
BACKSPACE="guess"
EOF

  # Применить раскладку
  if command -v setupcon &>/dev/null; then
    setupcon --force --skip-unicode 2>/dev/null || true
  fi

  # Убедиться что override_keylayout ОТСУТСТВУЕТ в xrdp.ini —
  # он жёстко фиксирует раскладку на уровне xrdp-протокола и
  # блокирует переключение setxkbmap из openbox autostart.
  local xrdp_ini="/etc/xrdp/xrdp.ini"
  if [ -f "${xrdp_ini}" ]; then
    cp "${xrdp_ini}" "${xrdp_ini}.bak_kbd" 2>/dev/null || true
    sed -i '/^xrdp\.override_keyboard_type=/d' "${xrdp_ini}"
    sed -i '/^xrdp\.override_keyboard_subtype=/d' "${xrdp_ini}"
    sed -i '/^xrdp\.override_keylayout=/d' "${xrdp_ini}"
    sed -i '/^; Force English/d' "${xrdp_ini}"
  fi

  log_success "Раскладки клавиатуры настроены (US/RU, Alt+Shift для переключения)"
}

configure_xrdp_ini() {
  log_info "Настраиваю xrdp.ini..."

  local xrdp_ini="/etc/xrdp/xrdp.ini"

  if grep -q '^crypt_level=' "${xrdp_ini}"; then
    sed -i 's/^crypt_level=.*/crypt_level=high/' "${xrdp_ini}"
  fi

  if grep -q '^security_layer=' "${xrdp_ini}"; then
    sed -i 's/^security_layer=.*/security_layer=negotiate/' "${xrdp_ini}"
  fi

  if grep -q '^tcp_keepalive=' "${xrdp_ini}"; then
    sed -i 's/^tcp_keepalive=.*/tcp_keepalive=true/' "${xrdp_ini}"
  fi

  log_success "xrdp.ini настроен"
}

add_xrdp_to_ssl_group() {
  if id xrdp &>/dev/null && getent group ssl-cert &>/dev/null; then
    usermod -aG ssl-cert xrdp 2>/dev/null || true
    log_info "Пользователь xrdp добавлен в группу ssl-cert"
  fi
}

enable_and_start() {
  log_info "Включаю и запускаю службы..."

  systemctl daemon-reload
  systemctl enable xrdp xrdp-sesman
  systemctl restart xrdp xrdp-sesman

  sleep 2

  if systemctl is-active --quiet xrdp; then
    log_success "xrdp запущен! Порт RDP: 3389"
  else
    log_warn "xrdp не запустился. Проверьте: journalctl -u xrdp -n 30"
  fi
}

configure_tint2() {
  log_info "Настраиваю tint2 (конфиг из репозитория)..."

  local cfg_dir="/etc/xdg/tint2"
  mkdir -p "${cfg_dir}"

  # Скачать конфиг из репозитория
  if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_RAW}/configs/tint2rc" -o "${cfg_dir}/tint2rc" 2>/dev/null && \
      log_success "tint2rc загружен из репозитория" || true
  elif command -v wget &>/dev/null; then
    wget -qO "${cfg_dir}/tint2rc" "${REPO_RAW}/configs/tint2rc" 2>/dev/null && \
      log_success "tint2rc загружен из репозитория" || true
  fi

  # Fallback — из локального репозитория
  if [ ! -s "${cfg_dir}/tint2rc" ] && [ -f "${INSTALL_DIR}/configs/tint2rc" ]; then
    cp "${INSTALL_DIR}/configs/tint2rc" "${cfg_dir}/tint2rc"
    log_success "tint2rc скопирован из локального репозитория"
  fi

  if [ -s "${cfg_dir}/tint2rc" ]; then
    log_success "tint2 настроен: ${cfg_dir}/tint2rc"
  else
    log_warn "Не удалось установить конфиг tint2, будет использован дефолтный"
  fi
}

configure_openbox_menu() {
  log_info "Настраиваю меню openbox (ПКМ на рабочем столе)..."

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

# Фон рабочего стола (без него — чёрный экран)
xsetroot -solid "#2e3440" &

# Переключение раскладки: Alt+Shift (us/ru)
setxkbmap -layout us,ru -option grp:alt_shift_toggle &

# X ресурсы (xterm: ПКМ = вставить из буфера)
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources &

# Панель задач (конфиг: /etc/xdg/tint2/tint2rc)
tint2 &
EOF

  log_success "Openbox autostart настроен"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  install_packages
  configure_startwm
  configure_keyboard_en
  configure_xrdp_ini
  configure_tint2
  configure_openbox_menu
  configure_xresources
  configure_openbox_autostart
  add_xrdp_to_ssl_group
  enable_and_start

  echo ""
  log_success "xrdp + openbox настроены!"
  log_info "Для подключения используйте RDP-клиент:"
  log_info "  Хост: <IP сервера>"
  log_info "  Порт: 3389"
  log_info "  Пользователь: root (или другой пользователь системы)"
  log_warn "Убедитесь что порт 3389 открыт в firewall"
}

main "$@"
