---
description: E2E тест установки AIProxy в LXC контейнере на Proxmox
---

# E2E тест AIProxy в LXC контейнере

Этот workflow пересоздаёт контейнер, устанавливает компоненты AIProxy через `install.sh` и проверяет их работу.

## Параметры (подставь перед запуском)

| Параметр     | Значение по умолчанию                              | Описание                  |
| ------------ | -------------------------------------------------- | ------------------------- |
| `PVE_HOST`   | `srv-hv1.ag.local`                                 | Proxmox-сервер (SSH)      |
| `CT_ID`      | `131`                                              | ID контейнера             |
| `ZFS_POOL`   | `pool2`                                            | ZFS-пул                   |
| `TEMPLATE`   | Debian 13 trixie                                   | Шаблон CT                 |
| `BRANCH`     | `lxqt`                                             | Ветка git-репо            |
| `COMPONENTS` | `--lxqt --xrdp --proxybridge --cliproxy --firefox` | Компоненты для install.sh |

## Шаги

### 1. Подключиться к Proxmox

```bash
ssh root@<PVE_HOST>
```

### 2. Сохранить MAC-адрес контейнера

```bash
grep 'hwaddr\|net0' /etc/pve/lxc/<CT_ID>.conf
```

Запомнить MAC-адрес (формат `XX:XX:XX:XX:XX:XX`).

### 3. Остановить и удалить контейнер

```bash
pct stop <CT_ID> || true
pct destroy <CT_ID> --purge
```

### 4. Найти шаблон Debian 13

```bash
pveam list local | grep debian-13
```

Если шаблона нет:

```bash
pveam update
pveam available | grep debian-13
pveam download local <имя_шаблона>
```

### 5. Пересоздать контейнер с сохранённым MAC

```bash
pct create <CT_ID> local:vztmpl/<шаблон>.tar.zst \
  --hostname aiproxy1 \
  --storage pool2 \
  --rootfs pool2:<размер_в_ГБ> \
  --memory 4096 \
  --swap 512 \
  --cores 4 \
  --net0 name=eth0,bridge=vmbr0,hwaddr=<СОХРАНЁННЫЙ_MAC>,ip=dhcp \
  --unprivileged 0 \
  --features nesting=1
```

> **ВАЖНО**: `--unprivileged 0` — привилегированный контейнер (нужен для ProxyBridge/nftables).
> `--features nesting=1` — для работы systemd внутри CT.

### 6. Запустить контейнер и установить git

```bash
pct start <CT_ID>
pct exec <CT_ID> -- bash -c "apt-get update -qq && apt-get install -y git"
```

### 7. Сделать ZFS-снимок (чистый Debian)

```bash
zfs snapshot pool2/subvol-<CT_ID>-disk-0@s<YYYYMMDD>
```

### 8. Зайти в контейнер, клонировать репо

```bash
pct enter <CT_ID>
git clone https://github.com/rsyuzyov/aiproxy.git ~/aiproxy
cd ~/aiproxy
git checkout <BRANCH>
```

### 9. Запустить установку

```bash
bash install.sh <COMPONENTS> -y
```

Дождаться завершения. Следить за ошибками в выводе.

### 10. Проверки после установки

#### Проверка служб

```bash
systemctl status proxybridge
systemctl status cliproxy-api
systemctl status xrdp
```

#### Проверка ProxyBridge

```bash
# Должен показать config.ini
cat /etc/proxybridge/config.ini

# Проверить что gen-args.sh формирует правильные аргументы
source /usr/local/lib/proxybridge/gen-args.sh && echo "ARGS: $PROXYBRIDGE_ARGS"

# Проверить что трафик ходит (DIRECT режим)
curl -sI https://ya.ru | head -3
```

#### Проверка RDP

Подключиться по RDP к IP контейнера на порт 3389.
Убедиться что LXQt загружается, в меню есть "Proxy Bridge".

#### Проверка GUI-обёртки

```bash
ls -la /usr/local/lib/proxybridge/gui-wrapper.sh
ls -la /usr/share/applications/proxybridge-gui.desktop
```

## Откат

Восстановить контейнер из ZFS-снимка:

```bash
pct stop <CT_ID>
zfs rollback pool2/subvol-<CT_ID>-disk-0@s<YYYYMMDD> -R
pct start <CT_ID>
```
