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

configure_sesman_ini() {
  log_info "Настраиваю sesman.ini (Policy=U)..."

  local sesman_ini="/etc/xrdp/sesman.ini"

  # Policy=U — ключ сессии только по user. Один юзер = одна сессия
  # независимо от IP/bpp/разрешения. Пользователь может подключаться
  # с работы, отключиться, подключиться из дома и попасть в ту же сессию.
  # Дефолтный Policy=Default (UBDI) плодит отдельную сессию на каждый IP.
  if grep -q '^Policy=' "${sesman_ini}"; then
    sed -i 's/^Policy=.*/Policy=U/' "${sesman_ini}"
  else
    log_warn "Policy= не найден в ${sesman_ini}, пропускаю"
  fi

  # [ChansrvLogging] — отдельный лог chansrv на каждый display.
  # По умолчанию блок пуст и chansrv пишет только в syslog, теряясь в общем шуме.
  # С LogFile=/var/log/xrdp-chansrv.${DISPLAY}.log падение/ошибки клиентских каналов
  # (clipboard, sound, fuse) видны per-display и легко коррелируют с сессией.
  # LogLevel=INFO достаточно для продакшена; DEBUG включать временно при расследовании.
  if ! grep -q '^LogFile=/var/log/xrdp-chansrv' "${sesman_ini}"; then
    sed -i '/^\[ChansrvLogging\]/a\
LogFile=/var/log/xrdp-chansrv.${DISPLAY}.log\
LogLevel=INFO\
EnableConsole=false\
EnableSyslog=true\
SyslogLevel=INFO' "${sesman_ini}"
  fi

  # EnableFuseMount оставляем дефолтным (true) — drive redirection в mstsc
  # "Local Resources → More → Drives" маунтится в /root/thinclient_drives/<USER>/<DRIVE>.
  # Требует LXC с доступом к /dev/fuse: в /etc/pve/lxc/<id>.conf добавить
  # features: fuse=1 (на Proxmox-хосте), рестарт контейнера. Без этого в логах
  # будет "fuse: device not found" — нефатально.

  log_success "sesman.ini настроен"
}

configure_reconnect_script() {
  log_info "Устанавливаю reconnectwm.sh (workaround для chansrv persistent-session)..."

  # Workaround для by-design проблемы xrdp 0.10.x: sesman не перезапускает
  # chansrv при реконнекте в persistent-сессию. При нештатном обрыве TCP
  # (sleep ноута клиента, сетевой таймаут) chansrv делает exit(0), оставляя
  # осиротевшие сокеты. Следующий реконнект получает chansrv_connect timeout →
  # buffer exchange, audio и fuse не работают до перезапуска сессии.
  #
  # Upstream fix: PR neutrinolabs/xrdp#3567 (merged 2025-07-21 в devel → 0.11+).
  # На 0.10.x не бэкпортирован.
  #
  # Скрипт вызывается sesman'ом на каждый реконнект. Если chansrv мёртв —
  # чистим сокеты и стартуем новый через systemd-run --scope.

  cat > /etc/xrdp/reconnectwm.sh <<'RECON'
#!/bin/bash
set -u

LOG=/var/log/xrdp-reconnectwm.log
exec >>"$LOG" 2>&1

DISP="${DISPLAY:-}"
SOCK_PATH="${XRDP_SOCKET_PATH:-/run/xrdp/sockdir/$(id -u)}"

echo "[$(date -Is)] reconnect display=$DISP user=$(id -un) sockdir=$SOCK_PATH"

if [ -z "$DISP" ]; then
    echo "  no DISPLAY in env, skip"
    exit 0
fi

# :10.0 или :10 → 10. Ниже сравниваем нормализованные ":N" без screen-суффикса.
DNUM="${DISP#:}"
DNUM="${DNUM%%.*}"
NORM_DISP=":$DNUM"

chansrv_alive_for_display() {
    local pid env_disp env_disp_norm
    for pid in $(pgrep -f '^/usr/sbin/xrdp-chansrv(\.real)?$' 2>/dev/null); do
        [ -r "/proc/$pid/environ" ] || continue
        env_disp=$(tr '\0' '\n' < "/proc/$pid/environ" | awk -F= '/^DISPLAY=/{print $2; exit}')
        [ -z "$env_disp" ] && continue
        env_disp_norm=":${env_disp#:}"
        env_disp_norm="${env_disp_norm%%.*}"
        if [ "$env_disp_norm" = "$NORM_DISP" ]; then
            echo "  found alive chansrv pid=$pid env_DISPLAY=$env_disp"
            return 0
        fi
    done
    return 1
}

if chansrv_alive_for_display; then
    echo "  chansrv alive for $DISP, nothing to do"
    exit 0
fi

LOCKFILE="/run/xrdp-chansrv-start.$DNUM.lock"
exec 9>"$LOCKFILE" 2>/dev/null || exit 0
if ! flock -n 9; then
    echo "  lock held by another reconnect, skip"
    exit 0
fi

echo "  chansrv dead for $DISP, cleaning orphan sockets"
rm -f \
    "$SOCK_PATH/xrdp_chansrv_socket_$DNUM" \
    "$SOCK_PATH/xrdp_chansrv_audio_in_socket_$DNUM" \
    "$SOCK_PATH/xrdp_chansrv_audio_out_socket_$DNUM" \
    "$SOCK_PATH/xrdpapi_$DNUM"

echo "  starting xrdp-chansrv in detached scope"
systemd-run \
    --unit="xrdp-chansrv-watchdog-${DNUM}-$$" \
    --scope --quiet \
    --setenv=DISPLAY="$DISP" \
    --setenv=XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
    --setenv=HOME="$HOME" \
    --setenv=USER="${USER:-$(id -un)}" \
    --setenv=LOGNAME="${LOGNAME:-$(id -un)}" \
    --setenv=LANG="${LANG:-C.UTF-8}" \
    --setenv=PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin" \
    --setenv=XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
    --setenv=XRDP_SOCKET_PATH="$SOCK_PATH" \
    --setenv=XRDP_SESSION="${XRDP_SESSION:-}" \
    --setenv=XRDP_PULSE_SINK_SOCKET="${XRDP_PULSE_SINK_SOCKET:-}" \
    --setenv=XRDP_PULSE_SOURCE_SOCKET="${XRDP_PULSE_SOURCE_SOCKET:-}" \
    /usr/sbin/xrdp-chansrv </dev/null >/dev/null 2>&1 &
disown

for i in 1 2 3 4 5 6; do
    sleep 0.5
    if [ -S "$SOCK_PATH/xrdp_chansrv_socket_$DNUM" ]; then
        echo "  chansrv socket appeared after ${i}x0.5s"
        exit 0
    fi
done
echo "  WARN: chansrv socket not created after 3s"
exit 0
RECON
  chmod +x /etc/xrdp/reconnectwm.sh
  log_success "reconnectwm.sh установлен"
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

  # XDG autostart — setxkbmap при каждом подключении.
  # xrdp каждый раз создаёт новый X-сервер, сбрасывая раскладку.
  # Этот .desktop срабатывает в любом DE с поддержкой XDG autostart (LXQt, XFCE и др.).
  mkdir -p /etc/xdg/autostart
  cat > /etc/xdg/autostart/setxkbmap.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Keyboard Layout
Exec=setxkbmap -model pc105 -layout us,ru -option grp:alt_shift_toggle
NoDisplay=true
X-XFCE-Autostart-Override=true
EOF

  log_success "Раскладки клавиатуры настроены (US/RU, Alt+Shift)"
}

configure_logrotate() {
  log_info "Настраиваю ротацию логов xrdp (daily, 7 дней, 100M)..."

  # Стандартный /etc/logrotate.d/xrdp наследует weekly+rotate4 от logrotate.conf
  # и не имеет размерного триггера. На terminal server с несколькими юзерами
  # при всплеске (много реконнектов) файл может раздуться между ротациями.
  # Особенно актуально при LogLevel=DEBUG.
  cat > /etc/logrotate.d/xrdp <<'EOF'
/var/log/xrdp*.log {
    daily
    rotate 7
    size 100M
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

  log_success "logrotate для xrdp настроен"
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
  configure_sesman_ini
  configure_reconnect_script
  configure_keyboard
  configure_logrotate
  add_xrdp_to_ssl_group
  enable_and_start

  echo ""
  log_success "xrdp-сервер настроен!"
  log_info "Теперь установите Desktop Environment:"
  log_info "  setup-openbox.sh  — Openbox + tint2"
  log_info "  setup-lxqt.sh     — LXQt (Debian 13)"
  log_warn "Убедитесь что порт 3389 открыт в firewall"
  echo ""
  log_info "Проброс дисков ПК→VM через RDP (drive redirection):"
  log_info "  1. На Proxmox-хосте в /etc/pve/lxc/<id>.conf добавить 'features: fuse=1'"
  log_info "  2. Рестартовать контейнер (pct stop <id> && pct start <id>)"
  log_info "  3. В mstsc: Local Resources → More → Drives"
  log_info "  4. В сессии диски появятся в /root/thinclient_drives/<USER>/"
}

main "$@"
