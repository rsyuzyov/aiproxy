#!/usr/bin/env bash
# =============================================================================
# Установка службы cliproxy-api
# Источник: https://github.com/router-for-me/CLIProxyAPI
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[cliproxy-api]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[cliproxy-api]${NC} $*"; }
log_error()   { echo -e "${RED}[cliproxy-api]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[cliproxy-api] OK:${NC} $*"; }

WORKDIR="/opt/cliproxy-api"
BIN="${WORKDIR}/cli-proxy-api"
SERVICE_NAME="cliproxy-api"
GITHUB_REPO="router-for-me/CLIProxyAPI"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# Вспомогательные скрипты храним в репозитории
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="${SCRIPT_DIR}/../configs/systemd"
DESKTOP_DIR="${SCRIPT_DIR}/../configs/desktop"
SELFUPDATE_BIN="${SCRIPT_DIR}/cliproxy-api-selfupdate.sh"
ROLLBACK_BIN="${SCRIPT_DIR}/cliproxy-api-rollback.sh"

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Запустите от имени root"
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) log_error "Неподдерживаемая архитектура: $(uname -m)"; exit 1 ;;
  esac
}

install_deps() {
  log_info "Проверка зависимостей..."
  local pkgs=()
  command -v curl    &>/dev/null || pkgs+=(curl)
  command -v python3 &>/dev/null || pkgs+=(python3)

  if [ "${#pkgs[@]}" -gt 0 ]; then
    log_info "Устанавливаю: ${pkgs[*]}"
    apt-get update -qq
    apt-get install -y "${pkgs[@]}"
  fi
}

get_latest_tag() {
  python3 - <<'PY'
import json, urllib.request
url = 'https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest'
req = urllib.request.Request(url, headers={'User-Agent': 'aiproxy-installer'})
with urllib.request.urlopen(req, timeout=15) as r:
    data = json.load(r)
print(data.get('tag_name', ''))
PY
}

download_binary() {
  local tag="$1"
  local arch="$2"
  local ver="${tag#v}"
  local asset="CLIProxyAPI_${ver}_linux_${arch}.tar.gz"
  local base="https://github.com/${GITHUB_REPO}/releases/download/${tag}"
  local asset_url="${base}/${asset}"
  local sums_url="${base}/checksums.txt"

  log_info "Скачиваю ${asset}..."

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap "rm -rf ${tmpdir}" EXIT

  curl -fsSL --connect-timeout 10 --max-time 120 -o "${tmpdir}/checksums.txt" "${sums_url}"
  curl -fsSL --connect-timeout 10 --max-time 120 -o "${tmpdir}/asset.tar.gz" "${asset_url}"

  # Проверка контрольной суммы
  local expected_line expected_sha actual_sha
  expected_line="$(grep -E "[[:space:]]${asset}$" "${tmpdir}/checksums.txt" | head -n 1)"
  expected_sha="$(echo "${expected_line}" | awk '{print $1}')"
  actual_sha="$(sha256sum "${tmpdir}/asset.tar.gz" | awk '{print $1}')"

  if [ "${expected_sha}" != "${actual_sha}" ]; then
    log_error "Ошибка контрольной суммы! expected=${expected_sha} actual=${actual_sha}"
    exit 1
  fi
  log_info "Контрольная сумма OK"

  # Извлечь бинарник
  mkdir -p "${tmpdir}/extract"
  tar -xzf "${tmpdir}/asset.tar.gz" -C "${tmpdir}/extract" cli-proxy-api
  chmod +x "${tmpdir}/extract/cli-proxy-api"

  # Backup если существует
  if [ -f "${BIN}" ]; then
    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    cp -a "${BIN}" "${WORKDIR}/cli-proxy-api.bak.${ts}"
    log_info "Резервная копия: ${WORKDIR}/cli-proxy-api.bak.${ts}"
  fi

  cp -f "${tmpdir}/extract/cli-proxy-api" "${WORKDIR}/cli-proxy-api.new"
  chmod 0755 "${WORKDIR}/cli-proxy-api.new"
  mv -f "${WORKDIR}/cli-proxy-api.new" "${BIN}"

  log_success "Бинарник установлен: ${BIN}"
}

install_selfupdate_script() {
  log_info "Устанавливаю скрипт selfupdate..."
  cat > "${SELFUPDATE_BIN}" <<'SCRIPT'
#!/usr/bin/env bash
set -u

log(){ echo "[cliproxy-api-selfupdate] $*"; }
fail(){ log "WARN: $*"; exit 0; }

CURL=(curl -fsSL --connect-timeout 5 --max-time 25 --retry 2 --retry-delay 1)
ARCH_RAW="$(uname -m || true)"
case "$ARCH_RAW" in
  x86_64|amd64) ARCH="amd64";;
  aarch64|arm64) ARCH="arm64";;
  *) fail "unsupported arch: $ARCH_RAW";;
esac

WORKDIR="/opt/cliproxy-api"
BIN="$WORKDIR/cli-proxy-api"

[ -d "$WORKDIR" ] || fail "missing dir: $WORKDIR"
[ -x "$BIN" ] || fail "missing executable: $BIN"

TAG="$(
  python3 - <<'PY' 2>/dev/null || true
import json, urllib.request
url = 'https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest'
req = urllib.request.Request(url, headers={'User-Agent': 'cliproxy-api-selfupdate'})
with urllib.request.urlopen(req, timeout=15) as r:
    data = json.load(r)
print(data.get('tag_name', ''))
PY
)"

[ -n "$TAG" ] || fail "could not fetch latest tag (GitHub API)"
VER="${TAG#v}"

ASSET="CLIProxyAPI_${VER}_linux_${ARCH}.tar.gz"
BASE="https://github.com/router-for-me/CLIProxyAPI/releases/download/${TAG}"
ASSET_URL="${BASE}/${ASSET}"
SUMS_URL="${BASE}/checksums.txt"

log "latest tag=$TAG asset=$ASSET"

TMPDIR="$(mktemp -d)" || fail "mktemp failed"
cleanup(){ rm -rf "$TMPDIR"; }
trap cleanup EXIT

cd "$TMPDIR" || fail "cd tmp failed"

"${CURL[@]}" -o checksums.txt "$SUMS_URL" || fail "failed to download checksums"
"${CURL[@]}" -o asset.tar.gz "$ASSET_URL" || fail "failed to download asset"

EXPECTED_LINE="$(grep -E "[[:space:]]${ASSET}$" checksums.txt | head -n 1 || true)"
[ -n "$EXPECTED_LINE" ] || fail "checksum line not found for ${ASSET}"
EXPECTED_SHA="$(echo "$EXPECTED_LINE" | awk '{print $1}')"
[ -n "$EXPECTED_SHA" ] || fail "could not parse expected sha"

ACTUAL_SHA="$(sha256sum asset.tar.gz | awk '{print $1}')"
if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
  fail "checksum mismatch for ${ASSET} expected=${EXPECTED_SHA} actual=${ACTUAL_SHA}"
fi

mkdir -p extract
( tar -xzf asset.tar.gz -C extract cli-proxy-api ) || fail "tar extract failed"
[ -f extract/cli-proxy-api ] || fail "binary missing in tar"
chmod +x extract/cli-proxy-api || true

CURRENT_VER="$($BIN 2>&1 | head -n 1 || true)"
NEW_VER="$(./extract/cli-proxy-api 2>&1 | head -n 1 || true)"
log "current: $CURRENT_VER"
log "new:     $NEW_VER"

if [ -n "$CURRENT_VER" ] && [ -n "$NEW_VER" ] && [ "$CURRENT_VER" = "$NEW_VER" ]; then
  log "already up-to-date"
  exit 0
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="$WORKDIR/cli-proxy-api.bak.${TS}"
cp -a "$BIN" "$BACKUP" || fail "backup failed"

cp -f extract/cli-proxy-api "$WORKDIR/cli-proxy-api.new" || fail "stage new binary failed"
chown root:root "$WORKDIR/cli-proxy-api.new" 2>/dev/null || true
chmod 0755 "$WORKDIR/cli-proxy-api.new" 2>/dev/null || true
mv -f "$WORKDIR/cli-proxy-api.new" "$BIN" || fail "replace failed"

log "updated OK (backup: $BACKUP)"
exit 0
SCRIPT
  chmod +x "${SELFUPDATE_BIN}"
  log_success "Скрипт selfupdate установлен: ${SELFUPDATE_BIN}"
}

install_rollback_script() {
  log_info "Устанавливаю скрипт rollback..."
  cat > "${ROLLBACK_BIN}" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[cliproxy-api-rollback] $*"; }
SERVICE="cliproxy-api.service"
WORKDIR="/opt/cliproxy-api"
BIN="$WORKDIR/cli-proxy-api"
LATEST_BAK="$(ls -1t $WORKDIR/cli-proxy-api.bak.* 2>/dev/null | head -n 1 || true)"
if [ -z "$LATEST_BAK" ]; then
  log "no backup found, skip"
  exit 0
fi
NOW="$(date -u +%s)"
MTIME="$(stat -c %Y "$LATEST_BAK" 2>/dev/null || echo 0)"
AGE="$((NOW - MTIME))"
if [ "$MTIME" -eq 0 ] || [ "$AGE" -gt 900 ]; then
  log "latest backup too old (age=${AGE}s), skip"
  exit 0
fi
cp -f "$LATEST_BAK" "$BIN"
chmod 0755 "$BIN" || true
chown root:root "$BIN" 2>/dev/null || true
log "restored $LATEST_BAK -> $BIN"
systemctl reset-failed "$SERVICE" || true
systemctl start "$SERVICE" || true
SCRIPT
  chmod +x "${ROLLBACK_BIN}"
  log_success "Скрипт rollback установлен: ${ROLLBACK_BIN}"
}

install_systemd_units() {
  log_info "Устанавливаю systemd units..."

  local main_template="${SYSTEMD_DIR}/${SERVICE_NAME}.service"
  local rollback_template="${SYSTEMD_DIR}/${SERVICE_NAME}-rollback.service"
  local selfupdate_template="${SYSTEMD_DIR}/${SERVICE_NAME}.service.d/10-selfupdate.conf"
  local onfailure_template="${SYSTEMD_DIR}/${SERVICE_NAME}.service.d/20-rollback.conf"

  for template in "${main_template}" "${rollback_template}" "${selfupdate_template}" "${onfailure_template}"; do
    if [ ! -f "${template}" ]; then
      log_error "Не найден шаблон systemd-файла: ${template}"
      exit 1
    fi
  done

  sed \
    -e "s|__WORKDIR__|${WORKDIR}|g" \
    -e "s|__BIN_PATH__|${BIN}|g" \
    "${main_template}" > "/etc/systemd/system/${SERVICE_NAME}.service"

  mkdir -p "/etc/systemd/system/${SERVICE_NAME}.service.d"

  # 10-selfupdate.conf содержит только комментарий (selfupdate перенесён в таймер)
  cp "${selfupdate_template}" "/etc/systemd/system/${SERVICE_NAME}.service.d/10-selfupdate.conf"

  cp "${onfailure_template}" "/etc/systemd/system/${SERVICE_NAME}.service.d/20-rollback.conf"

  sed \
    -e "s|__ROLLBACK_BIN__|${ROLLBACK_BIN}|g" \
    "${rollback_template}" > "/etc/systemd/system/${SERVICE_NAME}-rollback.service"

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"
  log_success "Systemd units установлены и включены"
}

install_updater_timer() {
  log_info "Устанавливаю таймер автообновления..."

  local update_bin="${SCRIPT_DIR}/cliproxy-api-update.sh"
  local updater_svc="${SYSTEMD_DIR}/cliproxy-api-updater.service"
  local updater_tmr="${SYSTEMD_DIR}/cliproxy-api-updater.timer"

  if [ ! -f "${updater_svc}" ] || [ ! -f "${updater_tmr}" ]; then
    log_warn "Шаблоны таймера не найдены в ${SYSTEMD_DIR}, пропускаю"
    return
  fi

  chmod +x "${update_bin}" 2>/dev/null || true

  sed -e "s|__CLIPROXY_UPDATE_BIN__|${update_bin}|g" \
    "${updater_svc}" > "/etc/systemd/system/cliproxy-api-updater.service"

  cp "${updater_tmr}" "/etc/systemd/system/cliproxy-api-updater.timer"

  systemctl daemon-reload
  systemctl enable --now "cliproxy-api-updater.timer"
  log_success "Таймер обновления установлен (ежедневно в 05:00)"
  log_info "Следующий запуск: $(systemctl show -P NextElapseUSecRealtime cliproxy-api-updater.timer 2>/dev/null || echo 'см. systemctl list-timers')"
}

create_default_config() {
  if [ -f "${WORKDIR}/config.yaml" ]; then
    log_info "config.yaml уже существует, пропускаю"
    return
  fi

  log_info "Создаю config.yaml из шаблона..."
  cp "${WORKDIR}/config.example.yaml" "${WORKDIR}/config.yaml" 2>/dev/null || \
  cat > "${WORKDIR}/config.yaml" <<'EOF'
# CLI Proxy API Configuration
# Документация: https://github.com/router-for-me/CLIProxyAPI

# Порт сервера
port: 8317

# TLS (HTTPS)
tls:
  enable: false

# Управление
remote-management:
  allow-remote: true
  secret-key: "123456"
  disable-control-panel: false
  panel-github-repository: "https://github.com/router-for-me/Cli-Proxy-API-Management-Center"

# Директория с учётными данными OAuth
auth-dir: "/root/.cli-proxy-api"

# API ключи (замените на свои)
api-keys:
  - "sk-changeme-1"

# Настройки
debug: false
commercial-mode: false
logging-to-file: true
logs-max-total-size-mb: 128
usage-statistics-enabled: true
force-model-prefix: true
request-retry: 3
max-retry-interval: 30

quota-exceeded:
  switch-project: true
  switch-preview-model: true

routing:
  strategy: "fill-first"

ws-auth: true
nonstream-keepalive-interval: 0
codex-instructions-enabled: false

gemini-api-key: []
oauth-model-alias: {}
EOF
  log_success "config.yaml создан"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_root
  install_deps

  local arch
  arch="$(detect_arch)"
  log_info "Архитектура: ${arch}"

  # Создать рабочую директорию
  mkdir -p "${WORKDIR}"

  # Получить последний тег
  log_info "Получаю последнюю версию с GitHub..."
  local tag
  tag="$(get_latest_tag)"
  if [ -z "${tag}" ]; then
    log_error "Не удалось получить информацию о последнем релизе"
    exit 1
  fi
  log_info "Последняя версия: ${tag}"

  # Скачать и установить бинарник
  download_binary "${tag}" "${arch}"

  # Создать конфиг если не существует
  create_default_config

  # Установить вспомогательные скрипты
  install_selfupdate_script
  install_rollback_script

  # Установить systemd units
  install_systemd_units

  # Установить таймер автообновления
  install_updater_timer

  # Запустить службу
  systemctl start "${SERVICE_NAME}.service"
  sleep 2

  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    log_success "Служба ${SERVICE_NAME} запущена!"
    log_info "Панель управления: http://localhost:8317/management.html"
    log_info "Конфигурация: ${WORKDIR}/config.yaml"
  else
    log_warn "Служба не запустилась. Проверьте: journalctl -u ${SERVICE_NAME} -n 20"
  fi

  # Ярлык в меню приложений
  local desktop_src="${DESKTOP_DIR}/cliproxy-api.desktop"
  if [ -f "${desktop_src}" ] && [ -d /usr/share/applications ]; then
    sed 's/\r$//' "${desktop_src}" > /usr/share/applications/cliproxy-api.desktop
    log_success "Ярлык добавлен в меню: CLIProxy API"
  fi
}

main "$@"
