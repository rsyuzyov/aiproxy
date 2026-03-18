#!/usr/bin/env bash
# =============================================================================
# Настройка LXQt как Desktop Environment для xrdp
# Требует: Debian 13 (trixie) + предварительной установки xrdp (setup-xrdp.sh)
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[lxqt]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[lxqt]${NC} $*"; }
log_error()   { echo -e "${RED}[lxqt]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[lxqt] OK:${NC} $*"; }

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

check_debian_version() {
  local ver
  ver=$(. /etc/os-release && echo "${VERSION_CODENAME:-unknown}")
  if [ "${ver}" != "trixie" ]; then
    log_warn "Обнаружен дистрибутив: ${ver}. LXQt рекомендуется только на Debian 13 (trixie)."
    log_warn "На Debian 12 (bookworm) некоторые пакеты могут отсутствовать."
  else
    log_info "Debian 13 (trixie) — OK"
  fi
}

install_packages() {
  log_info "Устанавливаю LXQt..."
  apt-get update -qq

  apt-get install -y \
    lxqt-core \
    lxqt-session \
    openbox \
    pcmanfm-qt \
    qterminal \
    xterm \
    lxqt-globalkeys \
    lxqt-panel \
    lxqt-policykit \
    lxqt-powermanagement \
    lxqt-runner \
    lximage-qt \
    obconf-qt

  log_success "Пакеты LXQt установлены"
}

configure_startwm() {
  log_info "Настраиваю /etc/xrdp/startwm.sh (lxqt-session)..."

  if [ ! -f "/etc/xrdp/startwm.sh.bak_orig" ]; then
    cp "/etc/xrdp/startwm.sh" "/etc/xrdp/startwm.sh.bak_orig" 2>/dev/null || true
  fi

  cat > "/etc/xrdp/startwm.sh" <<'EOF'
#!/bin/sh
# XRDP session startup — LXQt

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
[ -d "$XDG_RUNTIME_DIR" ] || { mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"; }

export DISPLAY=${DISPLAY:-:10}
export DESKTOP_SESSION=lxqt
export XDG_CURRENT_DESKTOP=LXQt

# Раскладка US/RU, Alt+Shift — задержка чтобы xrdpkeyb не перебил
(sleep 3 && setxkbmap -layout us,ru -option grp:alt_shift_toggle) &

exec dbus-launch --exit-with-session startlxqt
EOF

  chmod +x "/etc/xrdp/startwm.sh"
  log_success "startwm.sh → startlxqt"
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

set_lxqt_window_manager() {
  log_info "Устанавливаю openbox как оконный менеджер LXQt..."

  # LXQt хранит WM в своём конфиге сессии
  local lxqt_conf_dir="/etc/xdg/lxqt"
  mkdir -p "${lxqt_conf_dir}"

  # Глобальный конфиг сессии LXQt — window_manager
  local session_conf="${lxqt_conf_dir}/session.conf"
  if [ ! -f "${session_conf}" ]; then
    cat > "${session_conf}" <<'EOF'
[General]
window_manager=openbox
EOF
  else
    if grep -q '^window_manager=' "${session_conf}"; then
      sed -i 's/^window_manager=.*/window_manager=openbox/' "${session_conf}"
    else
      echo "window_manager=openbox" >> "${session_conf}"
    fi
  fi

  log_success "Оконный менеджер LXQt → openbox"
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
  check_debian_version

  install_packages
  configure_startwm
  configure_xresources
  set_lxqt_window_manager
  restart_xrdp

  echo ""
  log_success "LXQt настроен!"
  log_info "Подключитесь по RDP (порт 3389)"
  log_info "Файловый менеджер: pcmanfm-qt"
  log_info "Терминал: qterminal"
}

main "$@"
