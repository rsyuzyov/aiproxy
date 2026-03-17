#!/usr/bin/env bash
# =============================================================================
# Настройка xrdp-сервера (без Desktop Environment)
# Запускайте вместе с setup-openbox.sh или setup-lxqt.sh
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

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

  log_info "Устанавливаю xrdp, xorgxrdp, dbus-x11..."
  apt-get install -y \
    xrdp \
    xorgxrdp \
    dbus-x11 \
    x11-xserver-utils \
    x11-utils \
    xfonts-base \
    bash-completion

  log_success "Пакеты xrdp установлены"
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

configure_keyboard() {
  log_info "Настраиваю раскладки клавиатуры (US + RU, переключение Alt+Shift)..."

  cat > "/etc/default/keyboard" <<'EOF'
# KEYBOARD CONFIGURATION FILE
XKBMODEL="pc105"
XKBLAYOUT="us,ru"
XKBVARIANT=","
XKBOPTIONS="grp:alt_shift_toggle"
BACKSPACE="guess"
EOF

  if command -v setupcon &>/dev/null; then
    setupcon --force --skip-unicode 2>/dev/null || true
  fi

  # Убрать override_keylayout из xrdp.ini — он блокирует переключение раскладки
  local xrdp_ini="/etc/xrdp/xrdp.ini"
  if [ -f "${xrdp_ini}" ]; then
    cp "${xrdp_ini}" "${xrdp_ini}.bak_kbd" 2>/dev/null || true
    sed -i '/^xrdp\.override_keyboard_type=/d' "${xrdp_ini}"
    sed -i '/^xrdp\.override_keyboard_subtype=/d' "${xrdp_ini}"
    sed -i '/^xrdp\.override_keylayout=/d' "${xrdp_ini}"
    sed -i '/^; Force English/d' "${xrdp_ini}"
  fi

  # XKB-раскладка для xorg внутри xrdp
  local xconf_dir="/etc/X11/xrdp/xorg.conf.d"
  mkdir -p "${xconf_dir}"
  cat > "${xconf_dir}/20-keyboard.conf" <<'EOF'
Section "InputClass"
    Identifier "xrdp keyboard layout"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us,ru"
    Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
EOF

  log_success "Раскладки клавиатуры настроены (US/RU, Alt+Shift)"
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

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  install_packages
  configure_xrdp_ini
  configure_keyboard
  add_xrdp_to_ssl_group
  enable_and_start

  echo ""
  log_success "xrdp-сервер настроен!"
  log_info "Теперь установите Desktop Environment:"
  log_info "  setup-openbox.sh  — Openbox + tint2"
  log_info "  setup-lxqt.sh     — LXQt (Debian 13)"
  log_warn "Убедитесь что порт 3389 открыт в firewall"
}

main "$@"
