#!/usr/bin/env bash
# =============================================================================
# Установка AmneziaWG (ядро + утилиты awg / awg-quick)
# Совместимость: Debian/Ubuntu (amd64, arm64)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[amnezia]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[amnezia]${NC} $*"; }
log_error()   { echo -e "${RED}[amnezia]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[amnezia] OK:${NC} $*"; }

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

# Определить архитектуру
detect_arch() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "${arch}" in
    amd64|x86_64)  echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *)
      log_error "Неподдерживаемая архитектура: ${arch}"
      exit 1
      ;;
  esac
}

# Определить дистрибутив
detect_distro() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

install_via_ppa() {
  local distro="$1"
  log_info "Добавляю PPA freya-os/amneziawg..."

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq software-properties-common gnupg curl

  # PPA поддерживает Ubuntu; для Debian используем deb-файл
  if [ "${distro}" = "ubuntu" ]; then
    add-apt-repository -y ppa:freya-os/amneziawg
    apt-get update -qq
    apt-get install -y -qq amneziawg amneziawg-tools
    log_success "AmneziaWG установлен через PPA"
    return 0
  fi
  return 1
}

install_via_deb() {
  local arch="$1"
  log_info "Устанавливаю AmneziaWG через deb-пакет с GitHub Releases..."

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq curl

  # Определяем последнюю версию через GitHub API
  local api_url="https://api.github.com/repos/amnezia-vpn/amneziawg-linux-kernel-module/releases/latest"
  local version
  version="$(curl -fsSL "${api_url}" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"

  if [ -z "${version}" ]; then
    log_warn "Не удалось определить последнюю версию; использую fallback v1.0.1"
    version="v1.0.1"
  fi

  log_info "Версия AmneziaWG: ${version}"

  local deb_name="amneziawg-tools_${version#v}_${arch}.deb"
  local deb_url="https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/releases/download/${version}/${deb_name}"
  local tmp_deb="/tmp/${deb_name}"

  log_info "Скачиваю ${deb_url}..."
  if ! curl -fsSL -o "${tmp_deb}" "${deb_url}"; then
    log_warn "Не удалось скачать deb-пакет; пробую установить из исходников..."
    install_from_source
    return
  fi

  dpkg -i "${tmp_deb}" || apt-get install -f -y -qq
  rm -f "${tmp_deb}"
  log_success "AmneziaWG установлен через deb-пакет"
}

install_from_source() {
  log_info "Установка AmneziaWG из исходников (может занять несколько минут)..."

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq \
    build-essential \
    linux-headers-"$(uname -r)" \
    git \
    dkms \
    pkg-config \
    libelf-dev

  local src_dir="/tmp/amneziawg-src"
  rm -rf "${src_dir}"
  git clone --depth=1 \
    https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git \
    "${src_dir}"

  make -C "${src_dir}/src" -j"$(nproc)"
  make -C "${src_dir}/src" install
  modprobe amneziawg || true

  rm -rf "${src_dir}"
  log_success "AmneziaWG собран и установлен из исходников"
}

install_wg_tools_compat() {
  # wireguard-tools нужны для awg-quick и wg-quick обёртки
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq wireguard-tools
  log_success "wireguard-tools (wg-quick) установлены"
}

create_config_dir() {
  mkdir -p /etc/amnezia/amneziawg
  chmod 700 /etc/amnezia/amneziawg
  log_success "Каталог конфигов создан: /etc/amnezia/amneziawg/"
}

verify_installation() {
  local ok=true

  if command -v awg &>/dev/null; then
    log_success "awg найден: $(awg --version 2>/dev/null | head -1 || echo 'OK')"
  elif command -v wg &>/dev/null; then
    log_warn "awg не найден, но wg доступен — режим совместимости"
  else
    log_warn "awg/wg не найдены в PATH. Возможно потребуется перезагрузка или обновление PATH."
    ok=false
  fi

  if ! lsmod | grep -qE 'amneziawg|wireguard' 2>/dev/null; then
    log_warn "Модуль ядра amneziawg не загружен. Пробую загрузить..."
    modprobe amneziawg 2>/dev/null || modprobe wireguard 2>/dev/null || \
      log_warn "Не удалось загрузить модуль; может потребоваться перезагрузка"
  else
    log_success "Модуль ядра загружен"
  fi

  "${ok}" && return 0 || return 1
}

show_next_steps() {
  cat <<EOF

${GREEN}AmneziaWG установлен.${NC}

Чтобы настроить подключение, выполните:
  ${INSTALL_DIR:-~/aiproxy}/scripts/setup-amnezia-connection.sh /path/to/amnezia.conf

Управление туннелем вручную:
  awg-quick up   /etc/amnezia/amneziawg/amnezia0.conf
  awg-quick down /etc/amnezia/amneziawg/amnezia0.conf

Через systemd (автозапуск):
  systemctl enable --now awg-quick@amnezia0
  systemctl status awg-quick@amnezia0
EOF
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root

  log_info "Начинаю установку AmneziaWG..."

  local arch distro
  arch="$(detect_arch)"
  distro="$(detect_distro)"
  log_info "Система: ${distro} / ${arch}"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq

  # Попытка установки: PPA (Ubuntu) → deb (GitHub) → source
  if [ "${distro}" = "ubuntu" ]; then
    install_via_ppa "${distro}" || install_via_deb "${arch}"
  else
    install_via_deb "${arch}"
  fi

  install_wg_tools_compat
  create_config_dir
  verify_installation || true

  show_next_steps
}

main "$@"
