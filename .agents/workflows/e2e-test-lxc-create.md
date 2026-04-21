---
description: E2E тест установки AIProxy в LXC контейнере на Proxmox
---

# E2E тест AIProxy в LXC контейнере

Этот workflow пересоздаёт контейнер, устанавливает компоненты AIProxy через `install.sh` и проверяет их работу.

## Параметры

Все параметры вынесены в [`.agents/workflows/.env`](.env).
Если .agents/workflows/.env не существует то скопируй шаблон, сообщи пользователю и прекрати выполнение:

```bash
cp .agents/workflows/.env.example .agents/workflows/.env
# подправь значения под свой стенд
```

Перед каждым шагом подгрузи переменные:

```bash
set -a; . .agents/workflows/.env; set +a
```

Ожидаемые переменные: `PVE_HOST`, `CT_ID`, `ZFS_POOL`, `CT_HOSTNAME`, `CT_MEMORY`, `CT_SWAP`, `CT_CORES`, `CT_ROOTFS_GB`, `CT_BRIDGE`, `CT_TEMPLATE_PATTERN`, `REPO_URL`, `BRANCH`, `COMPONENTS`.

## Шаги

### 1. Подключиться к Proxmox

```bash
ssh "root@${PVE_HOST}"
```

### 2. Сохранить MAC-адрес контейнера

```bash
grep 'hwaddr\|net0' "/etc/pve/lxc/${CT_ID}.conf"
```

Запомнить MAC-адрес (формат `XX:XX:XX:XX:XX:XX`) → положить в переменную `CT_MAC`.

### 3. Остановить и удалить контейнер

```bash
pct stop "${CT_ID}" || true
pct destroy "${CT_ID}" --purge
```

### 4. Найти шаблон Debian 13

```bash
pveam list local | grep "${CT_TEMPLATE_PATTERN}"
```

Если шаблона нет:

```bash
pveam update
pveam available | grep "${CT_TEMPLATE_PATTERN}"
pveam download local <имя_шаблона>
```

### 5. Пересоздать контейнер с сохранённым MAC

```bash
TEMPLATE="$(pveam list local | grep "${CT_TEMPLATE_PATTERN}" | awk '{print $1}' | head -1)"

pct create "${CT_ID}" "${TEMPLATE}" \
  --hostname "${CT_HOSTNAME}" \
  --storage "${ZFS_POOL}" \
  --rootfs "${ZFS_POOL}:${CT_ROOTFS_GB}" \
  --memory "${CT_MEMORY}" \
  --swap "${CT_SWAP}" \
  --cores "${CT_CORES}" \
  --net0 "name=eth0,bridge=${CT_BRIDGE},hwaddr=${CT_MAC},ip=dhcp" \
  --unprivileged 0 \
  --features nesting=1
```

> **ВАЖНО**: `--unprivileged 0` — привилегированный контейнер (нужен для ProxyBridge/nftables).
> `--features nesting=1` — для работы systemd внутри CT.

### 6. Запустить контейнер и установить git

```bash
pct start "${CT_ID}"
pct exec "${CT_ID}" -- bash -c "apt-get update -qq && apt-get install -y git"
```

### 7. Сделать ZFS-снимок (чистый Debian)

```bash
zfs snapshot "${ZFS_POOL}/subvol-${CT_ID}-disk-0@s$(date +%Y%m%d)"
```

### 8. Зайти в контейнер, клонировать репо

```bash
pct exec "${CT_ID}" -- bash -c "git clone ${REPO_URL} ~/aiproxy && cd ~/aiproxy && git checkout ${BRANCH}"
```

### 9. Запустить установку

```bash
pct exec "${CT_ID}" -- bash -c "cd ~/aiproxy && bash install.sh ${COMPONENTS} -y"
```

Дождаться завершения. Следить за ошибками в выводе.

### 10. Проверки после установки

#### Проверка служб

```bash
pct exec "${CT_ID}" -- systemctl status proxybridge
pct exec "${CT_ID}" -- systemctl status cliproxy-api
pct exec "${CT_ID}" -- systemctl status xrdp
```

#### Проверка ProxyBridge

```bash
# Должен показать config.ini
pct exec "${CT_ID}" -- cat /etc/proxybridge/config.ini

# Проверить что gen-args.sh формирует правильные аргументы
pct exec "${CT_ID}" -- bash -c "source /usr/local/lib/proxybridge/gen-args.sh && echo ARGS: \$PROXYBRIDGE_ARGS"

# Проверить что трафик ходит (DIRECT режим)
pct exec "${CT_ID}" -- curl -sI https://ya.ru | head -3
```

#### Проверка RDP

Подключиться по RDP к IP контейнера на порт 3389.
Убедиться что LXQt загружается, в меню есть "Proxy Bridge".

#### Проверка GUI-обёртки

```bash
pct exec "${CT_ID}" -- ls -la /usr/local/lib/proxybridge/gui-wrapper.sh
pct exec "${CT_ID}" -- ls -la /usr/share/applications/proxybridge-gui.desktop
```

## Откат

Восстановить контейнер из ZFS-снимка:

```bash
pct stop "${CT_ID}"
zfs rollback "${ZFS_POOL}/subvol-${CT_ID}-disk-0@s$(date +%Y%m%d)" -R
pct start "${CT_ID}"
```
