# xrdp в aiproxy-контейнерах

## Факты

- Пакеты: `xrdp + xorgxrdp + dbus-x11`, Debian 13
- DE: LXQt (см. `scripts/setup-lxqt.sh`) или Openbox (`scripts/setup-openbox.sh`)
- Конфигурируется скриптом [scripts/setup-xrdp.sh](../../../../scripts/setup-xrdp.sh)

### Ключевые настройки sesman.ini

- `Policy=U` — ключ сессии только по user. Один юзер = одна сессия независимо от IP/bpp/разрешения (работа/дом — одна сессия)
- `KillDisconnected=false`, `DisconnectedTimeLimit=0`, `IdleTimeLimit=0` — persistent-сессии до явного logout (by design)
- `AllowRootLogin=true`, `AlwaysGroupCheck=false` — root и любые PAM-юзеры заходят без группы tsusers, каждый получает свой display

### Ключевые настройки xrdp.ini

- `crypt_level=high`
- `security_layer=negotiate`
- `tcp_keepalive=true`
- `LogLevel=INFO` (DEBUG только для диагностики)

### Раскладка

- `/etc/default/keyboard`: `XKBLAYOUT=us,ru`, `XKBOPTIONS=grp:alt_shift_toggle`
- `/etc/X11/xrdp/xorg.conf.d/20-keyboard.conf` — InputClass с `XkbLayout=us,ru`
- `/etc/xdg/autostart/setxkbmap.desktop` — возвращает us,ru при каждом входе (клиент RDP может прислать свою активную раскладку, xrdp её единолично навяжет; autostart перетирает)

### Logrotate

- `/etc/logrotate.d/xrdp`: `daily, rotate 7, size 100M, compress, delaycompress, copytruncate`
- 7 дней истории достаточно для расследований при первичной эксплуатации

## Грабли

- ⚠️ **chansrv делает exit(0) на нештатный обрыв TCP клиента** (sleep ноута, сетевой timeout). Штатный disconnect (close mstsc) chansrv переживает, но silent connection drop — нет. Upstream подтверждает в wiki (Copy-Paste-and-network-drives-don't-work-on-a-reconnect). Фикс [PR #3567](https://github.com/neutrinolabs/xrdp/pull/3567) merged 2025-07-21 в devel → 0.11+. В Debian 13 (0.10.1) и 0.10.x backport'а нет.

- ⚠️ **sesman 0.10.x не перезапускает chansrv при reconnect в persistent-сессию** — это by design. В sesman.log при реконнекте нет `Calling exec chansrv`, только запуск пустого `reconnectwm.sh`. Наш фикс — патч `reconnectwm.sh` в [scripts/setup-xrdp.sh](../../../../scripts/setup-xrdp.sh) `configure_reconnect_script`.

- ⚠️ **Policy=Default плодит сессии по IP.** Дефолт `Policy=Default` = UBDI (User+Bpp+Display+IP). Reconnect с другого IP → новая сессия, старая остаётся висеть вечно (с `KillDisconnected=false`). Правильно: `Policy=U`.

- ⚠️ **Мёртвые сессии после рестарта xrdp.** Если `systemctl restart xrdp xrdp-sesman` на контейнере с активным коннектом — может остаться осиротевший `startwm.sh` от убитой сессии. Проверять: `ps -ef | grep startwm` после рестарта.

- ⚠️ **Не городить watchdog-скрипты в интерактивной сессии.** Inline `bash -c 'while true; ...'` привязан к конкретному DISPLAY, остаётся зомби после гибели сессии, не восстанавливается, не зафиксирован нигде. Фиксы — только через `/etc/xrdp/*.ini`, `xorg.conf.d/*`, `xdg/autostart/*` или systemd unit.

- ⚠️ **bpp не подстраивается при reconnect.** Xorg стартует с bpp первого коннекта, xrdp не умеет динамически менять (в отличие от Windows RDSH). С Policy=U это не страшно — клиент видит существующую сессию «как есть».

## Диагностика

Типовой чек-лист при жалобе на clipboard/раскладку/сессии:

```bash
# на srv-hv1.ag.local:
pct exec <CT_ID> -- bash -c '
  echo "=== xrdp running ==="
  systemctl is-active xrdp xrdp-sesman
  echo "=== sessions ==="
  ps -eo pid,user,etime,cmd | grep -E "Xorg|xrdp-ses|chansrv" | grep -v grep
  echo "=== Policy ==="
  grep ^Policy /etc/xrdp/sesman.ini
  echo "=== chansrv alive per display ==="
  pgrep -af xrdp-chansrv
'
```

Если chansrv отсутствует для активного display — clipboard у пользователя мёртв, требуется его logout+login.

## Drive redirection (проброс дисков ПК→VM через RDP)

Аналог "Local Resources → Drives" в mstsc. Работает через xrdp-chansrv + FUSE mount в `/root/thinclient_drives/<USER>/<DRIVE>`.

**Требования для LXC-контейнера:**

1. На Proxmox-хосте в `/etc/pve/lxc/<id>.conf` добавить:
   ```
   features: fuse=1
   ```
2. Рестартовать контейнер (`pct stop <id> && pct start <id>`). ⚠️ Persistent-сессии xrdp умрут — планировать downtime.
3. В контейнере должен быть установлен `fuse3` (обычно уже есть).
4. В `/etc/xrdp/sesman.ini` `[Chansrv]`: `EnableFuseMount=true` (дефолт).
5. В mstsc клиента: `Local Resources → More → Drives`.

**Проверка:**
- `ls /dev/fuse` → character device 10:229
- `grep fuse /proc/filesystems` → есть `fuse`, `fusectl`, `fuseblk`
- После подключения: `ls /root/thinclient_drives/root/` → папки дисков клиента

**Что НЕ работает без drive redirection:**
- Ctrl+C на файле в Проводнике Windows + Ctrl+V в файловом менеджере VM (RDP clipboard передаёт только данные: текст/картинку/HTML, не `CF_HDROP`).

## Оживить clipboard без logout (ручной запуск chansrv)

Актуально для persistent-сессий, где sesman **не перезапустит** умерший chansrv при reconnect (by design в 0.10.x).

```bash
# на srv-hv1.ag.local
pct exec 107 -- systemd-run --unit=xrdp-chansrv-manual-10 --scope --quiet \
    --setenv=DISPLAY=:10 \
    --setenv=XAUTHORITY=/root/.Xauthority \
    --setenv=HOME=/root --setenv=USER=root --setenv=LANG=ru_RU.UTF-8 \
    --setenv=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin \
    /usr/sbin/xrdp-chansrv </dev/null >/dev/null 2>&1 &
```

Затем **disconnect + reconnect mstsc** (не logout). xrdp-wm нового worker'а подхватит `xrdp_chansrv_socket_10`. Проверено 2026-04-20 на контейнере 107.

## Ловля причины падения chansrv: wrapper + dpkg-divert

Если chansrv молча уходит в exit() (без OOM/segfault в dmesg), ставим shim чтобы поймать rc/signal/stderr на следующий крах:

```bash
# Wrapper
cat > /usr/local/sbin/xrdp-chansrv-wrapper.sh <<'WRAP'
#!/bin/bash
LOG=/var/log/xrdp-chansrv-wrapper.log
CRASHDIR=/var/crash/xrdp-chansrv
mkdir -p "$CRASHDIR"; cd "$CRASHDIR"; ulimit -c unlimited
echo "[$(date -Is)] START wrapper_pid=$$ ppid=$PPID display=${DISPLAY:-?} user=$(id -un) args=$*" >> "$LOG"
/usr/sbin/xrdp-chansrv.real "$@" 2>>"$LOG"
rc=$?
if [ $rc -gt 128 ]; then
    sig=$((rc-128)); echo "[$(date -Is)] EXIT rc=$rc signal=$sig ($(kill -l $sig 2>/dev/null))" >> "$LOG"
    ls -la "$CRASHDIR"/core* 2>/dev/null >> "$LOG" || true
else
    echo "[$(date -Is)] EXIT rc=$rc (normal)" >> "$LOG"
fi
exit $rc
WRAP
chmod +x /usr/local/sbin/xrdp-chansrv-wrapper.sh

# Divert оригинал, подсунуть wrapper
dpkg-divert --rename --divert /usr/sbin/xrdp-chansrv.real --add /usr/sbin/xrdp-chansrv
ln -sf /usr/local/sbin/xrdp-chansrv-wrapper.sh /usr/sbin/xrdp-chansrv

# [ChansrvLogging] в /etc/xrdp/sesman.ini — debug-логи chansrv в отдельный файл на display
# LogFile=/var/log/xrdp-chansrv.${DISPLAY}.log / LogLevel=DEBUG / EnableSyslog=true
```

⚠️ **dpkg-divert переживёт `apt upgrade xrdp`** — при обновлении пакета новый binary упадёт в `.real`, wrapper остаётся.

## Включение DEBUG-логов (временно)

```bash
sed -i "s/^LogLevel=.*/LogLevel=DEBUG/" /etc/xrdp/sesman.ini /etc/xrdp/xrdp.ini
systemctl restart xrdp xrdp-sesman
# после диагностики вернуть:
sed -i "s/^LogLevel=.*/LogLevel=INFO/" /etc/xrdp/sesman.ini /etc/xrdp/xrdp.ini
systemctl restart xrdp xrdp-sesman
```
