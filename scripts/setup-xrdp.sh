#!/usr/bin/env bash
# =============================================================================
# Настройка xrdp + openbox для RDP-доступа
# Особенности:
#  - Всегда английская раскладка (US) при входе
#  - Используется openbox-session через dbus-launch
# =============================================================================
set -euo pipefail

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

  log_info "Устанавливаю xrdp, openbox, dbus-x11..."
  apt-get install -y -qq \
    xrdp \
    xorgxrdp \
    openbox \
    dbus-x11 \
    x11-xserver-utils \
    x11-utils \
    xfonts-base \
    xterm

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
# Minimal stable XRDP session for container
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
[ -d $XDG_RUNTIME_DIR ] || { mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; }
export DESKTOP_SESSION=openbox
export XDG_CURRENT_DESKTOP=Openbox
exec dbus-launch --exit-with-session openbox-session
EOF

  chmod +x "/etc/xrdp/startwm.sh"
  log_success "startwm.sh настроен"
}

configure_keyboard_en() {
  log_info "Настраиваю английскую раскладку клавиатуры (всегда US при RDP-входе)..."

  # /etc/default/keyboard — системная раскладка
  cat > "/etc/default/keyboard" <<'EOF'
# KEYBOARD CONFIGURATION FILE
XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

  # Применить раскладку
  if command -v setupcon &>/dev/null; then
    setupcon --force --skip-unicode 2>/dev/null || true
  fi

  # Принудительно установить US раскладку в xrdp.ini (override)
  local xrdp_ini="/etc/xrdp/xrdp.ini"
  if [ -f "${xrdp_ini}" ]; then
    # Резервная копия
    cp "${xrdp_ini}" "${xrdp_ini}.bak_kbd" 2>/dev/null || true

    # Удалить старые override-настройки если есть
    sed -i '/^xrdp\.override_keyboard_type=/d' "${xrdp_ini}"
    sed -i '/^xrdp\.override_keyboard_subtype=/d' "${xrdp_ini}"
    sed -i '/^xrdp\.override_keylayout=/d' "${xrdp_ini}"

    # Добавить override в секцию [Xorg] или в конец файла
    # 0x00000409 = US English
    if grep -q '^\[Xorg\]' "${xrdp_ini}"; then
      # Добавить после [Xorg]
      sed -i '/^\[Xorg\]/a xrdp.override_keyboard_type=0x04\nxrdp.override_keyboard_subtype=0x01\nxrdp.override_keylayout=0x00000409' "${xrdp_ini}"
    else
      # Добавить в конец файла
      cat >> "${xrdp_ini}" <<'EOF'

; Force English (US) keyboard layout for all RDP sessions
xrdp.override_keyboard_type=0x04
xrdp.override_keyboard_subtype=0x01
xrdp.override_keylayout=0x00000409
EOF
    fi
  fi

  log_success "Раскладка клавиатуры настроена (US English)"
}

configure_xrdp_ini() {
  log_info "Настраиваю xrdp.ini..."

  local xrdp_ini="/etc/xrdp/xrdp.ini"

  # Настроить безопасность и производительность
  if grep -q '^crypt_level=' "${xrdp_ini}"; then
    sed -i 's/^crypt_level=.*/crypt_level=high/' "${xrdp_ini}"
  fi

  if grep -q '^security_layer=' "${xrdp_ini}"; then
    sed -i 's/^security_layer=.*/security_layer=negotiate/' "${xrdp_ini}"
  fi

  # tcp keepalive
  if grep -q '^tcp_keepalive=' "${xrdp_ini}"; then
    sed -i 's/^tcp_keepalive=.*/tcp_keepalive=true/' "${xrdp_ini}"
  fi

  log_success "xrdp.ini настроен"
}

add_xrdp_to_ssl_group() {
  # xrdp нужен доступ к SSL сертификатам
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

configure_openbox_autostart() {
  log_info "Настраиваю автозапуск Openbox..."

  local autostart_dir="/etc/xdg/openbox"
  mkdir -p "${autostart_dir}"

  # Создать autostart если не существует или пустой
  if [ ! -f "${autostart_dir}/autostart" ] || [ ! -s "${autostart_dir}/autostart" ]; then
    cat > "${autostart_dir}/autostart" <<'EOF'
#
# Openbox autostart
# Эти программы запускаются при старте Openbox-сессии.
#
EOF
    log_info "Создан файл autostart"
  fi

  log_success "Openbox настроен"
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
