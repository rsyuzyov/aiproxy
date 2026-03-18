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

  local session_content
  session_content=$(cat <<'EOF'
[General]
window_manager=openbox
EOF
  )

  # Глобальный конфиг (для всех пользователей, fallback)
  local global_dir="/etc/xdg/lxqt"
  mkdir -p "${global_dir}"
  _write_session_conf "${global_dir}/session.conf" "${session_content}"

  # Пользовательский конфиг для root (подавляет диалог "выберите WM")
  local user_dir="/root/.config/lxqt"
  mkdir -p "${user_dir}"
  _write_session_conf "${user_dir}/session.conf" "${session_content}"

  log_success "Оконный менеджер LXQt → openbox"
}

_write_session_conf() {
  local conf_file="$1" content="$2"
  if [ ! -f "${conf_file}" ]; then
    echo "${content}" > "${conf_file}"
  else
    if grep -q '^window_manager=' "${conf_file}"; then
      sed -i 's/^window_manager=.*/window_manager=openbox/' "${conf_file}"
    else
      echo "window_manager=openbox" >> "${conf_file}"
    fi
  fi
}

restart_xrdp() {
  log_info "Перезапускаю xrdp для применения изменений..."
  systemctl restart xrdp xrdp-sesman 2>/dev/null || true
}

configure_bash_completion() {
  log_info "Настраиваю bash-completion для tab-дополнения..."

  local bashrc="/root/.bashrc"
  if ! grep -q 'bash_completion' "$bashrc" 2>/dev/null; then
    cat >> "$bashrc" << 'EOF'

# Bash completion (tab-дополнение)
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF
    log_success "bash-completion добавлен в ~/.bashrc"
  else
    log_info "bash-completion уже подключён в ~/.bashrc"
  fi
}

install_ai_menu() {
  local configs_dir
  configs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../configs" && pwd)"
  local desktop_dir="${configs_dir}/desktop"

  log_info "Устанавливаю подменю AIProxy..."

  # .directory файл для категории
  if [ -f "${desktop_dir}/aiproxy.directory" ]; then
    sed 's/\r$//' "${desktop_dir}/aiproxy.directory" > /usr/share/desktop-directories/aiproxy.directory
  fi

  # XDG merge-menu для LXQt
  mkdir -p /etc/xdg/menus/applications-merged
  if [ -f "${desktop_dir}/aiproxy-menu.menu" ]; then
    sed 's/\r$//' "${desktop_dir}/aiproxy-menu.menu" > /etc/xdg/menus/applications-merged/aiproxy-menu.menu
  fi

  # Desktop-ярлыки AIProxy (aiproxy-*.desktop)
  for f in "${desktop_dir}"/aiproxy-*.desktop; do
    [ -f "$f" ] || continue
    local basename
    basename="$(basename "$f")"
    sed 's/\r$//' "$f" > "/usr/share/applications/${basename}"
  done

  log_success "Подменю AIProxy установлено ($(ls -1 "${desktop_dir}"/aiproxy-*.desktop 2>/dev/null | wc -l) ярлыков)"
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
  configure_bash_completion
  install_ai_menu
  set_lxqt_window_manager
  restart_xrdp

  echo ""
  log_success "LXQt настроен!"
  log_info "Подключитесь по RDP (порт 3389)"
  log_info "Файловый менеджер: pcmanfm-qt"
  log_info "Терминал: qterminal"
}

main "$@"
